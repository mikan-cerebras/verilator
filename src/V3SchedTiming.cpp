// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Code scheduling
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2003-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************
//
// Functions defined in this file are used by V3Sched.cpp to properly integrate
// static scheduling with timing features. They create external domains for
// variables, remap them to trigger vectors, and create timing resume/ready
// calls for the global eval loop. There is also a function that transforms
// forks into emittable constructs.
//
// See the internals documentation docs/internals.rst for more details.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3AstUserAllocator.h"
#include "V3ClassGraph.h"
#include "V3EmitCBase.h"
#include "V3Sched.h"

#include <unordered_map>
#include <unordered_set>

VL_DEFINE_DEBUG_FUNCTIONS;

namespace V3Sched {

//============================================================================
// Trigger indices of the external domains of each variable

std::map<const AstVarScope*, std::vector<uint32_t>>
TimingKit::externalTriggerIndices(const TriggerKit& trigKit) const {
    std::map<const AstVarScope*, std::vector<uint32_t>> result;
    for (const auto& vscpDomains : m_externalDomains) {
        std::vector<uint32_t>& indices = result[vscpDomains.first];
        for (const AstSenTree* const domainp : vscpDomains.second) {
            for (const AstSenItem* const itemp : domainp->sensespList()) {
                indices.push_back(trigKit.senItem2TrigIdx(itemp));
            }
        }
    }
    return result;
}

//============================================================================
// Creates a timing resume call (if needed, else returns null)

AstCCall* TimingKit::createResume(AstVarScope* trigVscp) {
    if (!m_resumeFuncp) {
        if (m_lbs.empty()) return nullptr;
        // Create global resume function
        AstNetlist* const netlistp = v3Global.rootp();
        AstScope* const scopeTopp = netlistp->topScopep()->scopep();
        m_resumeFuncp = new AstCFunc{netlistp->fileline(), "_timing_resume", scopeTopp, ""};
        m_resumeFuncp->dontCombine(true);
        m_resumeFuncp->isLoose(true);
        m_resumeFuncp->isConst(false);
        m_resumeFuncp->declPrivate(true);
        scopeTopp->addBlocksp(m_resumeFuncp);

        for (const auto& entry : m_lbs) {
            AstActive* const activep = entry.m_activep;
            activep->foreach([this](AstCMethodHard* const exprp) {
                if (exprp->method() != VCMethod::SCHED_RESUME) return;
                AstNodeExpr* const fromp = exprp->fromp();
                if (VN_AS(fromp->dtypep(), BasicDType)->keyword()
                    != VBasicDTypeKwd::TRIGGER_SCHEDULER) {
                    return;
                }
                AstCMethodHard* const moveToResumep = new AstCMethodHard{
                    fromp->fileline(), fromp->cloneTree(false),
                    VCMethod::SCHED_MOVE_TO_RESUME_QUEUE,
                    exprp->pinsp() ? exprp->pinsp()->cloneTree(true) : nullptr};
                moveToResumep->dtypeSetVoid();
                m_resumeFuncp->addStmtsp(moveToResumep->makeStmt());
            });
        }

        // Put all the timing actives in the resume function
        AstIf* dlyShedIfp = nullptr;
        for (const auto& entry : m_lbs) {
            AstActive* const activep = entry.m_activep;
            // Resume time delays last. For no particular reason other than
            // that's what we used to do prior to proper #0 support.
            AstVarRef* const schedrefp = VN_AS(
                VN_AS(VN_AS(activep->stmtsp(), StmtExpr)->exprp(), CMethodHard)->fromp(), VarRef);

            AstNode* const actionp = activep->stmtsp()->unlinkFrBackWithNext();
            if (schedrefp->varScopep()->dtypep()->basicp()->isDelayScheduler()) {
                FileLine* const flp = trigVscp->fileline();
                const std::set<uint32_t>& triggers = entry.m_triggers;
                AstTriggered* const condp
                    = new AstTriggered{flp, trigVscp, {triggers.begin(), triggers.end()}};
                dlyShedIfp = new AstIf{flp, condp};
                dlyShedIfp->addThensp(actionp);
            } else {
                m_resumeFuncp->addStmtsp(actionp);
            }
        }
        if (dlyShedIfp) m_resumeFuncp->addStmtsp(dlyShedIfp);

        // These are now spent, oispose of now empty AstActive instances
        m_lbs.deleteActives();
    }
    AstCCall* const callp = new AstCCall{m_resumeFuncp->fileline(), m_resumeFuncp};
    callp->dtypeSetVoid();
    return callp;
}

AstVarScope* TimingKit::getDelayScheduler(AstNetlist* const /*netlistp*/) {
    for (const auto& entry : m_lbs) {
        AstActive* const ap = entry.m_activep;
        // TODO: this triple VN_AS expression is ridiculous
        AstVarRef* const schedrefp
            = VN_AS(VN_AS(VN_AS(ap->stmtsp(), StmtExpr)->exprp(), CMethodHard)->fromp(), VarRef);
        AstVarScope* const vscp = schedrefp->varScopep();
        if (vscp->dtypep()->basicp()->isDelayScheduler()) return vscp;
    }
    // None found. Design doesn't use any time delays
    return nullptr;
}

//============================================================================
// Creates a timing ready call (if needed, else returns null)

AstCCall* TimingKit::createReady(AstVarScope* trigVscp) {
    if (!m_readyFuncp) {
        for (const auto& entry : m_lbs) {
            AstActive* const activep = entry.m_activep;
            auto* const resumep = VN_AS(VN_AS(activep->stmtsp(), StmtExpr)->exprp(), CMethodHard);
            UASSERT_OBJ(!resumep->nextp(), resumep, "Should be the only statement here");
            AstVarScope* const schedulerp = VN_AS(resumep->fromp(), VarRef)->varScopep();
            UASSERT_OBJ(schedulerp->dtypep()->basicp()->isDelayScheduler()
                            || schedulerp->dtypep()->basicp()->isTriggerScheduler()
                            || schedulerp->dtypep()->basicp()->isDynamicTriggerScheduler(),
                        schedulerp, "Unexpected type");
            if (!schedulerp->dtypep()->basicp()->isTriggerScheduler()) continue;
            // Create the global ready function only if we have trigger schedulers
            if (!m_readyFuncp) {
                AstNetlist* const netlistp = v3Global.rootp();
                AstScope* const scopeTopp = netlistp->topScopep()->scopep();
                m_readyFuncp = new AstCFunc{netlistp->fileline(), "_timing_ready", scopeTopp, ""};
                m_readyFuncp->dontCombine(true);
                m_readyFuncp->isLoose(true);
                m_readyFuncp->isConst(false);
                m_readyFuncp->declPrivate(true);
                scopeTopp->addBlocksp(m_readyFuncp);
            }

            FileLine* const flp = activep->sentreep()->fileline();

            // Create an 'AstIf' sensitive to the suspending triggers
            const std::set<uint32_t>& triggers = entry.m_triggers;
            AstTriggered* const condp
                = new AstTriggered{flp, trigVscp, {triggers.begin(), triggers.end()}};
            AstIf* const ifp = new AstIf{flp, condp};
            m_readyFuncp->addStmtsp(ifp);

            // Mark as ready the processes resumed on this sensitivity expression
            AstVarRef* const refp = new AstVarRef{flp, schedulerp, VAccess::READWRITE};
            AstCMethodHard* const callp = new AstCMethodHard{flp, refp, VCMethod::SCHED_READY};
            callp->dtypeSetVoid();
            if (resumep->pinsp()) callp->addPinsp(resumep->pinsp()->cloneTree(false));
            ifp->addThensp(callp->makeStmt());
        }
        // We still haven't created a ready function (no trigger schedulers), return null
        if (!m_readyFuncp) return nullptr;
    }
    AstCCall* const callp = new AstCCall{m_readyFuncp->fileline(), m_readyFuncp};
    callp->dtypeSetVoid();
    return callp;
}

//============================================================================
// Creates the timing kit and marks variables written by suspendables

class AwaitVisitor final : public VNVisitor {
    // NODE STATE
    //  AstSenTree::user1()  -> bool.               Set true if the sentree has been visited.
    //  AstCFunc::user1()    -> AstUser1Allocator.  See alocator below
    const VNUser1InUse m_inuser1;

    // STATE
    bool m_inProcess = false;  // Are we in a process?
    bool m_gatherVars = false;  // Should we gather written variables?
    AstScope* const m_scopeTopp;  // Scope at the top
    LogicByScope& m_lbs;  // Timing resume actives
    AstNodeStmt*& m_postUpdatesr;  // Post updates for the trigger eval function
    // Additional var sensitivities
    std::map<const AstVarScope*, std::set<AstSenTree*>>& m_externalDomains;
    std::unique_ptr<V3ClassGraph>
        m_classGraphp;  // class graph to get possibly called functions from a virtual call
    // What a process, or a function visited with a given value of m_gatherVars, adds directly
    struct CFuncCache final {
        std::set<AstSenTree*> m_processDomains;  // Sentrees awaited
        std::set<AstVarScope*> m_writtenBySuspendable;  // Variables written
        std::set<CFuncCache*> m_callees;  // Caches of the functions called
        bool m_visited = false;  // Whether the members are set
        // Strongly connected component (SCC) of the call graph, see visitScc()
        int m_sccIndex = -1;  // Order in the search, -1 if not visited yet
        int m_sccLowLink = 0;  // Lowest order reachable in the search
        bool m_onSccStack = false;  // Whether on m_sccStack
        size_t m_scc = 0;  // Index of its SCC in m_sccs
    };
    CFuncCache* m_cachep = nullptr;  // Cache of the current process or called function
    // Caches of called functions, by value of m_gatherVars
    AstUser1Allocator<AstCFunc, std::array<CFuncCache, 2>> m_cfuncsCache;
    // Caches of virtual calls, calling each possible function, by called function and m_gatherVars
    std::map<std::pair<const AstCFunc*, bool>, CFuncCache> m_virtualCallsCache;
    using DomainSet = std::set<AstSenTree*>;
    using CalleeSet = std::set<CFuncCache*>;
    std::set<DomainSet> m_domainSets;  // Distinct sets of sentrees, shared
    std::set<CalleeSet> m_calleeSets;  // Distinct caches called by processes
    struct Scc final {
        std::vector<CFuncCache*> m_members;  // Caches in the SCC
        const DomainSet* m_reachedp = nullptr;  // Sentrees awaited, directly or not
        // Sentrees of the processes reaching the SCC, directly or not
        std::set<const DomainSet*> m_callerDomainps;
    };
    std::vector<Scc> m_sccs;  // SCCs of caches called by processes, callees first
    std::vector<CFuncCache*> m_sccStack;  // Caches visited, not in an SCC yet
    int m_sccNextIndex = 0;  // Order of the next cache visited
    // What the processes writing a variable, or calling a cache, call and await directly
    struct Writers final {
        std::set<const CalleeSet*> m_calleeSets;  // Caches called
        std::set<const DomainSet*> m_domainSets;  // Sentrees awaited directly
    };
    std::unordered_map<AstVarScope*, Writers> m_varWriters;  // Writers by variable written
    std::unordered_map<CFuncCache*, Writers> m_calleeWriters;  // Writers by cache called
    // Sentrees reached from the caches called by processes, by distinct caches called
    std::unordered_map<const CalleeSet*, const DomainSet*> m_calleeSetDomains;
    // Count uses of not inlined writes to signals in suspendables
    VDouble0 m_notInlinedWritesInSuspendableUsage;

    // METHODS
    // Add arguments to a resume() call based on arguments in the suspending call
    void addResumePins(AstCMethodHard* const resumep, AstNodeExpr* pinsp) {
        AstCExpr* const exprp = VN_CAST(pinsp, CExpr);
        AstText* const textp = VN_CAST(exprp->nodesp(), Text);
        if (textp) {
            // The first argument, vlProcess, isn't used by any of resume() methods, skip it
            if ((pinsp = VN_CAST(pinsp->nextp(), NodeExpr))) {
                resumep->addPinsp(pinsp->cloneTree(false));
            }
        } else {
            resumep->addPinsp(pinsp->cloneTree(false));
        }
    }
    // Return a shared set of the sentrees in 'domains' and in the given sets
    const DomainSet* unionDomains(DomainSet domains, const std::set<const DomainSet*>& domainps) {
        if (domains.empty() && domainps.size() == 1) return *domainps.begin();
        for (const DomainSet* const domainsp : domainps) {
            domains.insert(domainsp->begin(), domainsp->end());
        }
        return &*m_domainSets.insert(std::move(domains)).first;
    }
    // Add the SCCs of a cache and of the caches it calls, with the sentrees they reach
    void visitScc(CFuncCache* const cachep) {
        // Tarjan's algorithm. An SCC is complete after all the SCCs it calls, so it gets the
        // sentrees they reach once, instead of each caller walking the call graph again
        cachep->m_sccIndex = cachep->m_sccLowLink = m_sccNextIndex++;
        m_sccStack.push_back(cachep);
        cachep->m_onSccStack = true;
        for (CFuncCache* const calleep : cachep->m_callees) {
            if (calleep->m_sccIndex < 0) {
                visitScc(calleep);
                cachep->m_sccLowLink = std::min(cachep->m_sccLowLink, calleep->m_sccLowLink);
            } else if (calleep->m_onSccStack) {
                cachep->m_sccLowLink = std::min(cachep->m_sccLowLink, calleep->m_sccIndex);
            }
        }
        if (cachep->m_sccLowLink != cachep->m_sccIndex) return;
        const size_t scc = m_sccs.size();
        m_sccs.emplace_back();
        CFuncCache* memberp;
        do {
            memberp = m_sccStack.back();
            m_sccStack.pop_back();
            memberp->m_onSccStack = false;
            memberp->m_scc = scc;
            m_sccs[scc].m_members.push_back(memberp);
        } while (memberp != cachep);
        DomainSet domains;
        std::set<const DomainSet*> calleeDomainps;
        for (const CFuncCache* const sccMemberp : m_sccs[scc].m_members) {
            const DomainSet& memberDomains = sccMemberp->m_processDomains;
            domains.insert(memberDomains.begin(), memberDomains.end());
            for (const CFuncCache* const calleep : sccMemberp->m_callees) {
                if (calleep->m_scc != scc)
                    calleeDomainps.insert(m_sccs[calleep->m_scc].m_reachedp);
            }
        }
        m_sccs[scc].m_reachedp = unionDomains(std::move(domains), calleeDomainps);
    }
    // Add the sentrees the writers await, directly or not, to 'domainps'
    void addWriterDomains(const Writers& writers, std::set<const DomainSet*>& domainps) {
        domainps.insert(writers.m_domainSets.begin(), writers.m_domainSets.end());
        for (const CalleeSet* const calleesp : writers.m_calleeSets) {
            // Once per distinct caches called, not per writer
            const auto pair = m_calleeSetDomains.emplace(calleesp, nullptr);
            if (pair.second) {
                std::set<const DomainSet*> calleeDomainps;
                for (const CFuncCache* const calleep : *calleesp) {
                    calleeDomainps.insert(m_sccs[calleep->m_scc].m_reachedp);
                }
                pair.first->second = unionDomains({}, calleeDomainps);
            }
            domainps.insert(pair.first->second);
        }
    }
    // Add the sentrees of a writer to the external domains of a variable
    void addExternalDomains(AstVarScope* const vscp, const DomainSet& domains) {
        m_externalDomains[vscp].insert(domains.begin(), domains.end());
        vscp->varp()->setWrittenBySuspendable();
    }
    // Set the external domains of the variables written by processes
    void computeExternalDomains() {
        // A variable written by a process, directly or through the functions it calls, gets the
        // sentrees the process awaits, directly or not. Compute these per SCC of the call graph,
        // as many processes, e.g. of each instance of a module, call the same functions
        for (const auto& pair : m_calleeWriters) {
            if (pair.first->m_sccIndex < 0) visitScc(pair.first);
        }
        for (const auto& pair : m_varWriters) {
            std::set<const DomainSet*> domainps;
            addWriterDomains(pair.second, domainps);
            for (const DomainSet* const domainsp : domainps) {
                addExternalDomains(pair.first, *domainsp);
            }
        }
        for (const auto& pair : m_calleeWriters) {
            addWriterDomains(pair.second, m_sccs[pair.first->m_scc].m_callerDomainps);
        }
        // Callers first
        for (auto it = m_sccs.rbegin(); it != m_sccs.rend(); ++it) {
            const size_t scc = m_sccs.rend() - it - 1;
            const DomainSet* const domainsp = unionDomains({}, it->m_callerDomainps);
            for (const CFuncCache* const cachep : it->m_members) {
                for (const CFuncCache* const calleep : cachep->m_callees) {
                    if (calleep->m_scc != scc) {
                        m_sccs[calleep->m_scc].m_callerDomainps.insert(domainsp);
                    }
                }
                for (AstVarScope* const vscp : cachep->m_writtenBySuspendable) {
                    // Count the variables written only in called functions
                    if (!m_externalDomains.count(vscp)) { ++m_notInlinedWritesInSuspendableUsage; }
                    addExternalDomains(vscp, *domainsp);
                }
            }
        }
    }
    // Create an active with a timing scheduler resume() call
    void createResumeActive(AstCAwait* const awaitp) {
        auto* const methodp = VN_AS(awaitp->exprp(), CMethodHard);
        AstVarScope* const schedulerp = VN_AS(methodp->fromp(), VarRef)->varScopep();
        AstSenTree* const sentreep = awaitp->sentreep();
        FileLine* const flp = sentreep->fileline();
        // Create a resume() call on the timing scheduler
        auto* const resumep = new AstCMethodHard{
            flp, new AstVarRef{flp, schedulerp, VAccess::READWRITE}, VCMethod::SCHED_RESUME};
        resumep->dtypeSetVoid();
        if (schedulerp->dtypep()->basicp()->isTriggerScheduler()) {
            UASSERT_OBJ(methodp->pinsp(), methodp,
                        "Trigger method should have pins from V3Timing");
            // The first pin is the ready boolean, the rest (if any) should be debug info
            // See V3Timing for details
            if (AstNode* const dbginfop = methodp->pinsp()->nextp()) {
                if (methodp->pinsp()) addResumePins(resumep, static_cast<AstNodeExpr*>(dbginfop));
            }
        } else if (schedulerp->dtypep()->basicp()->isDynamicTriggerScheduler()) {
            auto* const postp = resumep->cloneTree(false);
            postp->method(VCMethod::SCHED_DO_POST_UPDATES);
            m_postUpdatesr = AstNode::addNext(m_postUpdatesr, postp->makeStmt());
        }
        // Put it in an active
        AstActive* const activep = new AstActive{flp, "_timing", sentreep};
        activep->addStmtsp(resumep->makeStmt());
        m_lbs.add(m_scopeTopp, activep);
    }
    // Return the cache of a called function, visiting the function the first time
    CFuncCache* calledCache(AstCFunc* const nodep) {
        CFuncCache& cache = m_cfuncsCache(nodep)[static_cast<size_t>(m_gatherVars)];
        if (!cache.m_visited) {
            // Mark before visiting, so recursive calls only link to it
            cache.m_visited = true;
            VL_RESTORER(m_cachep);
            m_cachep = &cache;
            iterateChildren(nodep);
        }
        return &cache;
    }
    // Return the cache of a call, visiting the called functions the first time
    CFuncCache* callCache(AstNodeCCall* const nodep) {
        const auto& cfuncps = m_classGraphp->getCallPossibleCFuncs(nodep);
        if (cfuncps.empty()) return calledCache(nodep->funcp());
        // The possible functions depend only on the called function, so share their links
        CFuncCache& cache = m_virtualCallsCache[{nodep->funcp(), m_gatherVars}];
        if (!cache.m_visited) {
            cache.m_visited = true;
            for (AstCFunc* const cfuncp : cfuncps) cache.m_callees.insert(calledCache(cfuncp));
        }
        return &cache;
    }

    // VISITORS
    void visit(AstNodeProcedure* const nodep) override {
        UASSERT_OBJ(!m_inProcess && !m_gatherVars && !m_cachep, nodep, "Process in process?");
        CFuncCache procCache;
        m_cachep = &procCache;
        m_inProcess = true;
        m_gatherVars = nodep->isSuspendable();  // Only gather vars in a suspendable
        iterateChildren(nodep);
        // Record the process as a writer, see computeExternalDomains()
        const DomainSet* const domainsp = &*m_domainSets.insert(procCache.m_processDomains).first;
        const CalleeSet* const calleesp = &*m_calleeSets.insert(procCache.m_callees).first;
        for (AstVarScope* const vscp : procCache.m_writtenBySuspendable) {
            Writers& writers = m_varWriters[vscp];
            writers.m_calleeSets.insert(calleesp);
            writers.m_domainSets.insert(domainsp);
        }
        for (CFuncCache* const calleep : *calleesp) {
            Writers& writers = m_calleeWriters[calleep];
            writers.m_calleeSets.insert(calleesp);
            writers.m_domainSets.insert(domainsp);
        }
        m_cachep = nullptr;
        m_inProcess = false;
        m_gatherVars = false;
    }
    void visit(AstFork* nodep) override {
        VL_RESTORER(m_gatherVars);
        if (m_inProcess) m_gatherVars = true;
        // If not in a process, we don't need to gather variables or domains
        iterateChildren(nodep);
    }
    void visit(AstCAwait* nodep) override {
        if (AstSenTree* const sentreep = nodep->sentreep()) {
            if (!sentreep->user1SetOnce()) createResumeActive(nodep);
            if (m_inProcess) m_cachep->m_processDomains.insert(sentreep);
        }
        iterateChildren(nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (m_gatherVars && nodep->access().isWriteOrRW() && !nodep->varp()->ignoreSchedWrite()) {
            m_cachep->m_writtenBySuspendable.insert(nodep->varScopep());
        }
    }
    void visit(AstNodeCCall* const nodep) override {
        iterateChildren(nodep);
        if (!m_inProcess) return;  // Skip if not in process - nothing would be added to any set
        // We need to visit bodies of non-inlined functions
        m_cachep->m_callees.insert(callCache(nodep));
    }
    void visit(AstCFunc* const nodep) override {
        const auto& value = m_cfuncsCache(nodep);
        // Check whether it was already visited by calledCache()
        if (value[0].m_visited || value[1].m_visited) return;
        iterateChildren(nodep);
    }
    void visit(AstExprStmt* nodep) override { iterateChildren(nodep); }

    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit AwaitVisitor(AstNetlist* nodep, LogicByScope& lbs, AstNodeStmt*& postUpdatesr,
                          std::map<const AstVarScope*, std::set<AstSenTree*>>& externalDomains)
        : m_scopeTopp{nodep->topScopep()->scopep()}
        , m_lbs{lbs}
        , m_postUpdatesr{postUpdatesr}
        , m_externalDomains{externalDomains}
        , m_classGraphp{V3ClassGraph::build(nodep)} {
        iterate(nodep);
        computeExternalDomains();
    }
    ~AwaitVisitor() override {
        V3Stats::addStat("Scheduling, count of non-inlined signal writes in suspendables",
                         m_notInlinedWritesInSuspendableUsage);
    }
};

TimingKit prepareTiming(AstNetlist* const netlistp) {
    if (!v3Global.usesTiming()) return {};
    LogicByScope lbs;
    AstNodeStmt* postUpdates = nullptr;
    std::map<const AstVarScope*, std::set<AstSenTree*>> externalDomains;
    { AwaitVisitor{netlistp, lbs, postUpdates, externalDomains}; }
    return {std::move(lbs), postUpdates, std::move(externalDomains)};
}

//============================================================================
// Visits all forks and transforms their sub-statements into separate functions.

// Transform all forked processes into functions
class TransformForksVisitor final : public VNVisitor {
    // NODE STATE
    //  AstVar::user1()  -> bool.  Set true if the variable was declared before the current fork.
    const VNUser1InUse m_inuser1;

    // STATE
    bool m_inClass = false;  // Are we in a class?
    bool m_beginHasAwaits = false;  // Does the current begin have awaits?
    AstFork* m_forkp = nullptr;  // Current fork
    AstCFunc* m_funcp = nullptr;  // Current function

    // METHODS
    // Remap local vars referenced by the given fork function
    // TODO: We should only pass variables to the fork that are
    // live in the fork body, but for that we need a proper data
    // flow analysis framework which we don't have at the moment
    void remapLocals(AstCFunc* const funcp, AstCCall* const callp) {
        const VNUser2InUse user2InUse;  // AstVarScope -> AstVarScope: var to remap to
        funcp->foreach([&](AstNodeVarRef* refp) {
            AstVar* const varp = refp->varp();
            AstVarScope* const vscp = refp->varScopep();
            AstBasicDType* const dtypep = varp->dtypep()->basicp();
            // If not a fork..join, copy. All write refs should've been handled by V3Fork
            bool passByValue = !m_forkp->joinType().join();
            if (vscp->forkByValue()) {
                // Set just before the fork, for its processes to get by value
                passByValue = true;
            } else if (!varp->isFuncLocal()) {
                // Not func local. Its lifetime is longer than the forked process. Skip
                return;
            } else if (!varp->user1()) {
                // Not declared before the fork. It cannot outlive the forked process
                return;
            } else if (dtypep && dtypep->isForkSync()) {
                // We can just pass it by value to the new function
                passByValue = true;
            }
            // Remap the reference
            if (!vscp->user2p()) {
                // Clone the var to the new function
                AstVar* const newvarp
                    = new AstVar{varp->fileline(), VVarType::BLOCKTEMP, varp->name(), varp};
                newvarp->funcLocal(true);
                newvarp->direction(passByValue ? VDirection::INPUT : VDirection::REF);
                funcp->addArgsp(newvarp);
                AstVarScope* const newvscp
                    = new AstVarScope{newvarp->fileline(), funcp->scopep(), newvarp};
                funcp->scopep()->addVarsp(newvscp);
                vscp->user2p(newvscp);
                callp->addArgsp(new AstVarRef{refp->fileline(), vscp,
                                              passByValue ? VAccess::READ : VAccess::READWRITE});
            }
            AstVarScope* const newvscp = VN_AS(vscp->user2p(), VarScope);
            refp->varScopep(newvscp);
            refp->varp(newvscp->varp());
        });
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_inClass);
        m_inClass = VN_IS(nodep, Class);
        iterateChildren(nodep);
    }
    void visit(AstCFunc* nodep) override {
        VL_RESTORER(m_funcp);
        m_funcp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstVar* nodep) override {
        if (!m_forkp) nodep->user1(true);
    }
    void visit(AstFork* nodep) override {
        if (m_forkp) return;  // Handle forks in forks after moving them to new functions
        VL_RESTORER(m_forkp);
        m_forkp = nodep;
        iterateChildrenConst(nodep);  // Const, so we don't iterate the calls twice
        // Replace self with the function calls (no co_await, as we don't want the main
        // process to suspend whenever any of the children do)
        // V3Dead could have removed all statements from the fork, so guard against it
        // Inline begins now that they are not needed
        AstNode* resp = nullptr;
        if (AstNode* const declsp = nodep->declsp()) {
            resp = AstNode::addNext(resp, declsp->unlinkFrBackWithNext());
        }
        if (AstNode* const stmtsp = nodep->stmtsp()) {
            resp = AstNode::addNext(resp, stmtsp->unlinkFrBackWithNext());
        }
        while (AstBegin* const beginp = nodep->forksp()) {
            if (AstNode* const declsp = beginp->declsp()) {
                resp = AstNode::addNext(resp, declsp->unlinkFrBackWithNext());
            }
            if (AstNode* const stmtsp = beginp->stmtsp()) {
                resp = AstNode::addNext(resp, stmtsp->unlinkFrBackWithNext());
            }
            VL_DO_DANGLING(pushDeletep(beginp->unlinkFrBack()), beginp);
        }
        if (resp) {
            nodep->replaceWith(resp);
        } else {
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstBegin* nodep) override {
        UASSERT_OBJ(m_forkp, nodep, "Begin outside of a fork");
        // Start with children, so later we only find awaits that are actually in this begin
        m_beginHasAwaits = false;
        iterateChildrenConst(nodep);
        if (!nodep->stmtsp()) return;
        if (!m_beginHasAwaits && !nodep->needProcess()) return;

        UASSERT_OBJ(!nodep->name().empty(), nodep, "Begin needs a name");
        // Create a function to put this begin's statements in
        FileLine* const flp = nodep->fileline();
        AstCFunc* const newfuncp = new AstCFunc{flp, m_funcp->name() + "__" + nodep->name(),
                                                m_funcp->scopep(), "VlCoroutine"};

        m_funcp->addNextHere(newfuncp);
        newfuncp->isLoose(m_funcp->isLoose());
        newfuncp->slow(m_funcp->slow());
        newfuncp->isConst(m_funcp->isConst());
        newfuncp->declPrivate(true);
        // Create the call to the function
        AstCCall* const callp = new AstCCall{flp, newfuncp};
        callp->dtypeSetVoid();
        // If we're in a class, add a vlSymsp arg
        if (m_inClass) {
            newfuncp->addStmtsp(new AstCStmt{flp, "VL_KEEP_THIS;", VCStmtType::KEEP_THIS});
            newfuncp->argTypes(EmitCUtil::symClassVar());
            callp->argTypes("vlSymsp");
        }
        // Put the begin's statements in the function
        if (AstNode* const declsp = nodep->declsp()) {
            newfuncp->addStmtsp(declsp->unlinkFrBackWithNext());
        }
        if (AstNode* const stmtsp = nodep->stmtsp()) {
            newfuncp->addStmtsp(stmtsp->unlinkFrBackWithNext());
        }
        // Replace the body of the begin with a call to the newly created function
        nodep->addStmtsp(callp->makeStmt());
        // Propagate if needs process
        if (nodep->needProcess()) newfuncp->setNeedProcess();
        remapLocals(newfuncp, callp);
    }
    void visit(AstCAwait* nodep) override {
        m_beginHasAwaits = true;
        iterateChildrenConst(nodep);
    }

    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit TransformForksVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~TransformForksVisitor() override = default;
};

void transformForks(AstNetlist* const netlistp) {
    if (!v3Global.usesTiming()) return;
    { TransformForksVisitor{netlistp}; }
    V3Global::dumpCheckGlobalTree("transform_forks", 0, dumpTreeEitherLevel() >= 3);
}

}  // namespace V3Sched
