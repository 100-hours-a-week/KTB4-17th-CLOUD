// Exercise the actual bootstrap's post-install acceptance check without any Jenkins IO.
def loader=new GroovyClassLoader(getClass().classLoader)
['groovy.json.JsonSlurperClassic','hudson.init.InitMilestone','jenkins.model.Jenkins',
 'org.jenkinsci.plugins.pipeline.modeldefinition.parser.Converter',
 'org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval',
 'org.jenkinsci.plugins.scriptsecurity.scripts.languages.GroovyLanguage'].findAll { !it.startsWith('groovy.') }.each { String name ->
    int i=name.lastIndexOf('.'); loader.parseClass('package '+name.substring(0,i)+'; class '+name.substring(i+1)+' {}')
}
loader.parseClass('package hudson.model; class Result {static final String SUCCESS="SUCCESS"}')
loader.parseClass('package org.jenkinsci.plugins.workflow.cps; class CpsFlowDefinition {String script; boolean sandbox}')
loader.parseClass('package jenkins.triggers; class ReverseBuildTrigger {String upstreamProjects; Object threshold}')
loader.parseClass('package org.jenkinsci.plugins.workflow.job.properties; class PipelineTriggersJobProperty {List triggers}')
loader.parseClass('package org.jenkinsci.plugins.workflow.job.properties; class DisableConcurrentBuildsJobProperty {boolean abortPrevious}')
loader.parseClass('''package org.jenkinsci.plugins.workflow.job
class WorkflowJob {
    String fullName; Object definition; List allProperties=[]; boolean disabled; boolean buildable=true
    boolean isDisabled(){disabled}; boolean isBuildable(){buildable}
}''')
Class bootstrap=loader.parseClass(new File(args[0],'bootstrap-staging-cd.groovy'))
def checker=bootstrap.newInstance()
def create={String type,Map fields->loader.loadClass(type).newInstance(fields)}
for (String name in ['cd/backend-dev','cd/ai-dev','cd/backend-main','cd/ai-main']) {
    String upstream='ci/'+(name.contains('backend')?'backend/':'ai/')+(name.endsWith('dev')?'dev':'main')
    for(String mode in ['good','disabled','unbuildable','duplicate-trigger-property','missing-trigger','foreign-trigger',
                       'relative-trigger','wrong-threshold','missing-concurrency','abort-concurrency','foreign-definition']) {
        def trigger=create('jenkins.triggers.ReverseBuildTrigger',[upstreamProjects:mode=='foreign-trigger'?'/ci/foreign/main':
                mode=='relative-trigger'?upstream:'/'+upstream,threshold:mode=='wrong-threshold'?'UNSTABLE':'SUCCESS'])
        def triggers=create('org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty',
                [triggers:(mode == 'missing-trigger' ? [] : [trigger])])
        def concurrency=create('org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty',
                [abortPrevious:mode=='abort-concurrency'])
        List properties=[triggers]
        if(mode!='missing-concurrency') properties.add(concurrency)
        if(mode=='duplicate-trigger-property') properties.add(triggers)
        def job=create('org.jenkinsci.plugins.workflow.job.WorkflowJob',[fullName:name,
                definition:create('org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition',
                    [script:mode=='foreign-definition'?'foreign':'reviewed',sandbox:false]),
                allProperties:properties,disabled:mode=='disabled',buildable:mode!='unbuildable'])
        boolean rejected=false
        try{checker.verifyInstalledCoordinator(job,'reviewed',upstream)}catch(IllegalStateException expected){
            rejected=true
            if(mode=='disabled') assert expected.message.contains('operator')
        }
        assert rejected==(mode!='good'): 'Bootstrap accepted invalid state '+name+' '+mode
        assert job.disabled==(mode=='disabled'): 'Bootstrap changed the operator disable state'
    }
}
println 'Bootstrap verification checks passed: enabled/buildable, exact trigger/concurrency, operator pause preserved'
