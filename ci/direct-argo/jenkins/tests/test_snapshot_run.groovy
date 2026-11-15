// Actual snapshotRun execution against in-memory Jenkins API boundary types.
def loader = new GroovyClassLoader(getClass().classLoader)
loader.parseClass('package com.cloudbees.groovy.cps; @interface NonCPS {}')
loader.parseClass('''package jenkins.model
class Jenkins {
    static Jenkins instance = new Jenkins()
    Map items = [:]; List globalNodeProperties = []
    static Jenkins get() { instance }
    Object getItemByFullName(String name, Class type) { items[name] }
}''')
loader.parseClass('''package org.jenkinsci.plugins.workflow.job
class WorkflowJob {
    String fullName; Object parent; Object branchProperty; Map builds = [:]; Object lastBuild
    Object getProperty(Class type) { branchProperty }
    Object getBuildByNumber(int number) { builds[number] }
}''')
loader.parseClass('package org.jenkinsci.plugins.workflow.multibranch; class BranchJobProperty { Object branch }')
loader.parseClass('package org.jenkinsci.plugins.github_branch_source; class GitHubSCMSource {String repoOwner; String repository}')
loader.parseClass('package jenkins.scm.api; class SCMRevisionAction {String sourceId; Object revision}')
loader.parseClass('package jenkins.plugins.git; class AbstractGitSCMSource {static class SCMRevisionImpl {String hash; Object head}}')
loader.parseClass('package hudson.plugins.git.util; class BuildData {List remoteUrls; Object lastBuiltRevision}')
loader.parseClass('package hudson.model; class Cause {static class UpstreamCause {String upstreamProject; int upstreamBuild}}')
loader.parseClass('package hudson.model; class BooleanParameterValue {String name; boolean value}')
loader.parseClass('package hudson.model; class StringParameterValue {String name; String value}')
loader.parseClass('package hudson.model; class ParametersAction {List parameters}')
loader.parseClass('package hudson.model; class Result {static final String SUCCESS = "SUCCESS"}')
loader.parseClass('package hudson.slaves; class EnvironmentVariablesNodeProperty {Map envVars}')
loader.parseClass('package org.jenkinsci.plugins.workflow.cps; class EnvActionImpl {Map overriddenEnvironment}')
Class runType = loader.parseClass('''class LocalRun {
    int number; String result; boolean building; List actions; List causes; Object previousBuild; Object artifactManager
    boolean isBuilding() { building }
    List getActions(Class type) { actions.findAll { type.isInstance(it) } }
    Object getAction(Class type) { getActions(type).find { true } }
}''')
Class builtType = loader.parseClass('class BuiltRevision {String sha1String; List branches}')
Class branchType = loader.parseClass('class BuiltBranch {String name; String sha; String getSHA1String() {sha}}')
File base = new File(args[0])
String assembled = new File(base,'coordinator-pipeline.groovy').getText('UTF-8').replace('/* COORDINATOR_POLICY */',
        new File(base,'CoordinatorPolicy.groovy').getText('UTF-8'))
Class pipeline = loader.parseClass(assembled,'SnapshotCoordinator.groovy')
Class policy = loader.loadClass('CoordinatorPolicy')
Class jenkins = loader.loadClass('jenkins.model.Jenkins')
def construct = { String type, Map fields -> loader.loadClass(type).newInstance(fields) }
String sha = 'a' * 40
for (String jobName in ['cd/backend-dev','cd/ai-dev','cd/backend-main','cd/ai-main']) {
    Map profile = policy.profile(jobName)
    for (String mode in ['bound-action','legacy-bound-builddata','legacy-no-builddata','legacy-foreign-builddata',
                         'legacy-foreign-branch','foreign-source-id','duplicate-action','builddata-only','detached-bound',
                         'detached-legacy','exact-coordinator-cause']) {
        Map branch = [name:profile.source_branch, sourceId:'expected-source']
        def github = construct('org.jenkinsci.plugins.github_branch_source.GitHubSCMSource',
                [repoOwner:'100-hours-a-week',repository:profile.family=='be'?'KTB4-17th-BE':'KTB4-17th-AI'])
        def parent = new Expando(getSCMSource:{ String sourceId -> assert sourceId=='expected-source'; github })
        def property = construct('org.jenkinsci.plugins.workflow.multibranch.BranchJobProperty',[branch:branch])
        def job = construct('org.jenkinsci.plugins.workflow.job.WorkflowJob',
                [fullName:profile.source_job,parent:parent,branchProperty:property])
        Map env = profile.family=='be' ? [SOURCE_COMMIT:sha, DEPLOYMENT_REQUESTED:'false', STAGING_REQUESTED:'false',
                   PRODUCTION_REQUESTED:'false',PUBLICATION_REQUESTED:'true'] :
                  [GIT_COMMIT:sha,AUTO_DEPLOY:'false',MANUAL_GITOPS_PR:'false',PUBLISH_IMAGE:'true']
        List actions = [construct('org.jenkinsci.plugins.workflow.cps.EnvActionImpl',[overriddenEnvironment:env]),
                construct('hudson.model.ParametersAction',[parameters:[construct('hudson.model.BooleanParameterValue',[name:'PUSH_IMAGE',value:true])]])]
        if (mode!='builddata-only') {
            String sourceId = mode.startsWith('legacy-') || mode=='detached-legacy' ? null :
                    mode=='foreign-source-id' ? 'different-source' : 'expected-source'
            def revision = construct('jenkins.plugins.git.AbstractGitSCMSource$SCMRevisionImpl',[hash:sha,head:[name:profile.source_branch]])
            actions.add(construct('jenkins.scm.api.SCMRevisionAction',[sourceId:sourceId,revision:revision]))
            if (mode=='duplicate-action') actions.add(actions.last())
        }
        if (mode!='legacy-no-builddata' && mode!='bound-action' && mode!='exact-coordinator-cause') {
            String repo = mode=='legacy-foreign-builddata' ? 'someone/foreign' : profile.source_repository
            String branchName = mode=='legacy-foreign-branch' ? 'origin/foreign' :
                    mode.startsWith('detached-') ? 'HEAD' : 'origin/'+profile.source_branch
            def built = builtType.newInstance(sha1String:sha,branches:[branchType.newInstance(name:branchName,sha:sha)])
            actions.add(construct('hudson.plugins.git.util.BuildData',
                    [remoteUrls:['https://github.com/'+repo+'.git'],lastBuiltRevision:built]))
        }
        def cause = construct('hudson.model.Cause$UpstreamCause',[upstreamProject:profile.coordinator,upstreamBuild:20])
        def run = runType.newInstance(number:9,result:'SUCCESS',building:false,actions:actions,causes:[cause])
        job.builds[9] = run
        jenkins.get().items[profile.source_job] = job
        Script script = (Script) pipeline.newInstance()
        boolean rejected = false
        Map snapshot
        try { snapshot=script.snapshotRun(profile,9); policy.validateRun(profile,snapshot,true) }
        catch (IllegalArgumentException expected) {rejected=true}
        boolean unsafe = mode in ['legacy-no-builddata','legacy-foreign-builddata','legacy-foreign-branch',
                                  'foreign-source-id','duplicate-action','detached-legacy']
        assert rejected==unsafe: 'Snapshot provenance decision incorrect for '+jobName+' '+mode
        if (!unsafe) {
            assert snapshot.source_sha==sha && snapshot.branch==profile.source_branch
            assert snapshot.coordinator_build_numbers==[20] && snapshot.called_by_coordinator
        }
    }
}
// The scan calls the actual snapshotRun and exactArtifacts methods; only the
// Jenkins storage objects are in memory. Count all examined Runs toward the bound.
for (String jobName in ['cd/backend-dev','cd/ai-dev','cd/backend-main','cd/ai-main']) {
    Map profile=policy.profile(jobName)
    def job=jenkins.get().getItemByFullName(profile.source_job,loader.loadClass('org.jenkinsci.plugins.workflow.job.WorkflowJob'))
    def baseline=job.getBuildByNumber(9)
    for (String mode in ['valid','foreign-source-id','foreign-repository','wrong-sha','failed','missing-artifacts','none','bounded']) {
        def candidate={int number,String revisionSha,boolean push,String variant ->
            Map env=new LinkedHashMap(baseline.getAction(loader.loadClass('org.jenkinsci.plugins.workflow.cps.EnvActionImpl')).overriddenEnvironment)
            env[profile.family=='be'?'SOURCE_COMMIT':'GIT_COMMIT']=revisionSha
            env[profile.family=='be'?'PUBLICATION_REQUESTED':'PUBLISH_IMAGE']=push.toString()
            def revision=construct('jenkins.plugins.git.AbstractGitSCMSource$SCMRevisionImpl',[hash:revisionSha,head:[name:profile.source_branch]])
            List actions=[construct('org.jenkinsci.plugins.workflow.cps.EnvActionImpl',[overriddenEnvironment:env]),
                    construct('hudson.model.ParametersAction',[parameters:[construct('hudson.model.BooleanParameterValue',[name:'PUSH_IMAGE',value:push])]]),
                    construct('jenkins.scm.api.SCMRevisionAction',[sourceId:variant=='foreign-source-id'?'foreign':variant=='foreign-repository'?null:'expected-source',revision:revision])]
            if(variant=='foreign-repository') {
                def built=builtType.newInstance(sha1String:revisionSha,branches:[branchType.newInstance(name:'origin/'+profile.source_branch,sha:revisionSha)])
                actions.add(construct('hudson.plugins.git.util.BuildData',[remoteUrls:['https://github.com/foreign/repo.git'],lastBuiltRevision:built]))
            }
            def storage=new Expando(root:{->new Expando(child:{String path->new Expando(
                    isFile:{->variant!='missing-artifacts'},open:{->new ByteArrayInputStream('archived-evidence'.bytes)})})})
            runType.newInstance(number:number,result:variant=='failed'?'FAILURE':'SUCCESS',building:false,actions:actions,causes:[],artifactManager:storage)
        }
        List builds=[candidate(100,sha,false,'valid')]
        if(mode=='bounded') {
            (99..51).each{int n->builds.add(candidate(n,sha,false,'valid'))}
            builds.add(candidate(50,sha,true,'valid'))
        } else if(mode!='none') {
            builds.add(candidate(99,mode=='wrong-sha'?'b'*40:sha,true,mode))
            if(mode!='valid') builds.add(candidate(98,sha,true,'valid'))
        }
        builds.eachWithIndex{run,int index->run.previousBuild=index+1<builds.size()?builds[index+1]:null}
        job.builds=builds.collectEntries{[(it.number):it]};job.lastBuild=builds[0]
        Script scanner=(Script)pipeline.newInstance()
        Map found=scanner.findReusablePublisher(profile,sha)
        assert found.scan_limit==50 && found.scanned<=50
        if(mode in ['none','bounded']) assert found.publisher==null
        else {
            assert found.publisher.run_id==profile.source_job+(mode=='valid'?'#99':'#98')
            assert found.publisher.source_commit==sha && found.publisher.push_image
        }
        if(mode=='bounded') assert found.scanned==50: 'Bounded scan examined a 51st Run'
    }
}
println 'Snapshot checks passed: bound SCM source IDs, legacy repository/branch proof and exact upstream cause'
