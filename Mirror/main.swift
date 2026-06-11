import AppKit

let args = CommandLine.arguments

// Headless mode: launchd triggers workflow execution via --run-workflow <id>
if args.count >= 3 && args[1] == "--run-workflow" {
    let workflowId = args[2]
    let engine = WorkflowEngine()
    engine.restoreScheduledWorkflows()

    let semaphore = DispatchSemaphore(value: 0)
    var success = false

    engine.executeWorkflow(workflowId: workflowId) { result in
        success = result
        semaphore.signal()
    }

    semaphore.wait()
    exit(success ? 0 : 1)
}

// GUI mode
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
