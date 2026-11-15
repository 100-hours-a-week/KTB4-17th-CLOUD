// A syntax check with boundary type stubs, not a Jenkins integration test.
def loader = new GroovyClassLoader(getClass().classLoader)
loader.parseClass('package com.cloudbees.groovy.cps; @interface NonCPS {}')
[
 'hudson.model.Action', 'hudson.model.CauseAction', 'hudson.model.BooleanParameterValue', 'hudson.model.ParametersAction',
 'hudson.model.StringParameterValue', 'hudson.slaves.EnvironmentVariablesNodeProperty',
 'hudson.plugins.git.util.BuildData', 'org.jenkinsci.plugins.workflow.multibranch.BranchJobProperty', 'jenkins.model.Jenkins',
 'jenkins.scm.api.SCMRevisionAction', 'jenkins.util.Timer', 'hudson.security.ACL',
 'org.jenkinsci.plugins.github_branch_source.GitHubSCMSource',
 'org.jenkinsci.plugins.workflow.cps.EnvActionImpl', 'org.jenkinsci.plugins.workflow.job.WorkflowJob',
 'com.cloudbees.hudson.plugins.folder.Folder', 'jenkins.triggers.ReverseBuildTrigger',
 'org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition',
 'org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty',
 'org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty',
 'org.jenkinsci.plugins.pipeline.modeldefinition.parser.Converter',
 'org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval',
 'org.jenkinsci.plugins.scriptsecurity.scripts.languages.GroovyLanguage'
].each { String name ->
    int split = name.lastIndexOf('.')
    loader.parseClass('package ' + name.substring(0, split) + '; class ' + name.substring(split + 1) + ' {}')
}
loader.parseClass('package hudson.model; class Cause { static class UpstreamCause {} }')
loader.parseClass('package jenkins.plugins.git; class AbstractGitSCMSource { static class SCMRevisionImpl {} }')
loader.parseClass('package hudson.init; enum InitMilestone { JOB_CONFIG_ADAPTED, COMPLETED }')
Class resultType = loader.parseClass('package hudson.model; class Result { static final Result SUCCESS = new Result() }')
File base = new File(args[0])
String template = new File(base, 'coordinator-pipeline.groovy').getText('UTF-8')
String assembled = template.replace('/* COORDINATOR_POLICY */', new File(base, 'CoordinatorPolicy.groovy').getText('UTF-8'))
Class coordinator = loader.parseClass(assembled, 'AssembledCoordinator.groovy')
loader.parseClass(new File(base, 'install-coordinators.groovy'))
loader.parseClass(new File(base, 'bootstrap-staging-cd.groovy'))
// Execute only the declaration boundary. Options and every stage body are
// deliberately left uncalled: no Jenkins API, source CI, node or server is used.
for (List names in [['cd/backend-dev', 'ci/backend/dev'], ['cd/ai-dev', 'ci/ai/dev'],
                   ['cd/backend-main', 'ci/backend/main'], ['cd/ai-main', 'ci/ai/main']]) {
    List observed = []
    def triggers = new Expando()
    triggers.upstream = { Map values ->
        assert resultType.isInstance(values.threshold): 'upstream threshold must be a hudson.model.Result, not a String'
        assert values.threshold.is(resultType.SUCCESS)
        assert values.upstreamProjects.toString() == '/' + names[1]
        observed.add(values)
    }
    def declaration = new Expando()
    declaration.agent = { Object ignored -> }
    Map localFlags = [:]
    declaration.environment = { Closure body ->
        body.delegate = localFlags
        body.resolveStrategy = Closure.DELEGATE_FIRST
        body.call()
    }
    declaration.options = { Closure ignored -> }
    declaration.stages = { Closure ignored -> }
    declaration.triggers = { Closure body ->
        body.delegate = triggers
        body.resolveStrategy = Closure.DELEGATE_FIRST
        body.call()
    }
    Binding binding = new Binding(currentBuild:new Expando(fullProjectName:names[0]), none:'none')
    binding.setVariable('pipeline', { Closure body ->
        body.delegate = declaration
        body.resolveStrategy = Closure.DELEGATE_FIRST
        body.call()
    })
    Script script = (Script) coordinator.newInstance()
    script.binding = binding
    script.run()
    assert observed.size() == 1
    String flag = names[0].endsWith('dev') ? 'AI_STAGING_AUTO_DEPLOY_ENABLED' : 'AI_PROD_AUTO_DEPLOY_ENABLED'
    assert localFlags[flag].toString() == (names[0].startsWith('cd/ai-') ? 'true' : 'false')
    assert localFlags.values().count { it.toString() == 'true' } == (names[0].startsWith('cd/ai-') ? 1 : 0)
}
println 'Coordinator, installer and bootstrap Groovy syntax passed (Jenkins boundary types stubbed)'
