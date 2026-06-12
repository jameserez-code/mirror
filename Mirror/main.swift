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

    // If completion never fired (engine hang), force exit after 5-minute safety timeout
    if !success {
        let fallback = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 300) { fallback.signal() }
        fallback.wait()
    }

    exit(success ? 0 : 1)
}

// GUI mode
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
