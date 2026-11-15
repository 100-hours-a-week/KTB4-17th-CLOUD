// Execute the real installer update function against the documented Jenkins
// append-only Job.addProperty boundary, without a Jenkins instance or files.
def loader = new GroovyClassLoader(getClass().classLoader)
['hudson.slaves.EnvironmentVariablesNodeProperty',
 'jenkins.model.Jenkins', 'org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition'].each { String name ->
    int split = name.lastIndexOf('.')
    loader.parseClass('package ' + name.substring(0, split) + '; class ' + name.substring(split + 1) + ' {}')
}
loader.parseClass('''package com.cloudbees.hudson.plugins.folder
class Folder {
    Map jobs = [:]; Map durableConfigs = [:]; boolean crashAfterPersist; Closure factory
    Object createProjectFromXML(String name, InputStream stream) {
        byte[] bytes = stream.bytes
        def doc = javax.xml.parsers.DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(new ByteArrayInputStream(bytes))
        String description = doc.getElementsByTagName('description').item(0).textContent
        String script = doc.getElementsByTagName('script').item(0).textContent
        if (jobs.containsKey(name)) throw new IOException('already exists')
        durableConfigs[name] = new String(bytes, 'UTF-8')
        jobs[name] = factory.call(description, script)
        if (crashAfterPersist) throw new IOException('injected crash after initial config persistence')
        return jobs[name]
    }
}''')
loader.parseClass('package hudson.model; class Result { static final String SUCCESS = "SUCCESS" }')
loader.parseClass('''package jenkins.triggers
class ReverseBuildTrigger {
    String upstreamProjects; Object threshold; boolean active = false; int stopped = 0
    ReverseBuildTrigger(String source) { upstreamProjects = source }
    void setThreshold(Object value) { threshold = value }
}''')
loader.parseClass('''package org.jenkinsci.plugins.workflow.job.properties
class DisableConcurrentBuildsJobProperty {}''')
loader.parseClass('''package org.jenkinsci.plugins.workflow.job.properties
class PipelineTriggersJobProperty {
    List triggers
    PipelineTriggersJobProperty(List values) { triggers = values }
    void stopTriggers() { triggers.each { it.active = false; it.stopped++ } }
    void startTriggers(boolean fresh) { triggers.each { it.active = true } }
}''')
loader.parseClass('''package org.jenkinsci.plugins.workflow.job
import org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty
class WorkflowJob {
    List properties = []; String description; Object definition
    Object getProperty(Class type) { properties.find { type.isInstance(it) } }
    void addProperty(Object property) {
        properties.add(property)
        if (property instanceof PipelineTriggersJobProperty) {
            def first = getProperty(PipelineTriggersJobProperty)
            first.stopTriggers(); first.startTriggers(true)
        }
    }
    void removeProperty(Object property) {
        if (property instanceof PipelineTriggersJobProperty) property.stopTriggers()
        properties.remove(property)
    }
}''')
Class installer = loader.parseClass(new File(args[0], 'install-coordinators.groovy'))
def script = installer.newInstance()
Class workflow = loader.loadClass('org.jenkinsci.plugins.workflow.job.WorkflowJob')
Class disabled = loader.loadClass('org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty')
Class property = loader.loadClass('org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty')
Class trigger = loader.loadClass('jenkins.triggers.ReverseBuildTrigger')
def job = workflow.newInstance()
def unrelated = new Object()
job.addProperty(unrelated)
List oldTriggers = [trigger.newInstance('old/source'), trigger.newInstance('older/source')]
oldTriggers.each { job.addProperty(property.newInstance([it])) }
job.addProperty(disabled.newInstance()); job.addProperty(disabled.newInstance())
for (String source in ['ci/backend/dev', 'ci/backend/dev', 'ci/ai/dev', 'ci/backend/main', 'ci/ai/main']) {
    script.replaceCoordinatorProperties(job, source)
    assert job.properties.count { property.isInstance(it) } == 1
    assert job.properties.count { disabled.isInstance(it) } == 1
    assert job.properties.any { it.is(unrelated) }: 'Unrelated job properties were removed'
    def selected = job.getProperty(property).triggers
    assert selected.size() == 1 && selected[0].upstreamProjects == '/' + source
    assert selected[0].threshold == 'SUCCESS' && selected[0].active
}
assert oldTriggers.every { !it.active && it.stopped > 0 }
// Crash immediately after initial XML persistence must leave durable ownership,
// allowing a normal reapply to complete the trigger and concurrency properties.
def folder=loader.loadClass('com.cloudbees.hudson.plugins.folder.Folder').newInstance()
folder.factory={String description,String definition->workflow.newInstance(description:description,definition:definition)}
folder.crashAfterPersist=true
boolean crashed=false
try {
    script.createManagedCoordinator(folder,'backend-main',
            'Managed: star23-source-free-direct-coordinator-v2\nreviewed SHA', 'reviewed <script> & source')
} catch(IOException expected) { crashed=true }
assert crashed && folder.durableConfigs.size()==1
assert folder.jobs['backend-main'].description.startsWith('Managed: star23-source-free-direct-coordinator-v2')
assert folder.jobs['backend-main'].definition=='reviewed <script> & source'
assert script.managedCoordinator('cd/backend-main',folder.jobs['backend-main'].description)
script.replaceCoordinatorProperties(folder.jobs['backend-main'],'ci/backend/main')
assert folder.jobs['backend-main'].properties.count{property.isInstance(it)}==1
assert folder.jobs['backend-main'].getProperty(property).triggers[0].upstreamProjects=='/ci/backend/main'
assert script.managedCoordinator('cd/backend-dev', 'Managed: star23-source-free-staging-coordinator-v1\nold definition')
assert script.managedCoordinator('cd/ai-dev', 'Managed: star23-source-free-staging-coordinator-v1')
assert script.managedCoordinator('cd/ai-main', 'Managed: star23-source-free-direct-coordinator-v2\ncurrent definition')
assert !script.managedCoordinator('cd/ai-main', 'Managed: star23-source-free-staging-coordinator-v1')
assert !script.managedCoordinator('cd/backend-dev', 'An unrelated job mentioning Managed: star23-source-free-staging-coordinator-v1')
assert !script.managedCoordinator('cd/other', 'Managed: star23-source-free-direct-coordinator-v2')
println 'Installer reapply checks passed: no duplicate properties, current trigger active, unrelated properties preserved'
