import XCTest
@testable import WakeMacCore

final class ExecutionPlanTests: XCTestCase {
    private func task(_ id: String, deps: [String] = [], condition: PlanDependencyCondition = .success) -> PlanTask {
        .init(id: id, command: "true", directory: "/tmp", dependencies: deps, condition: condition)
    }
    func testRejectsInvalidGraphsBeforeExecution() throws {
        for tasks in [[task("a"), task("a")], [task("a", deps: ["missing"])],
                      [task("a", deps: ["b"]), task("b", deps: ["a"])], [task("a", deps: ["a"])]] {
            XCTAssertThrowsError(try ExecutionPlan(title: "invalid", tasks: tasks).validated())
        }
        XCTAssertThrowsError(try ExecutionPlan(title: "empty", tasks: []).validated())
        XCTAssertThrowsError(try ExecutionPlan(title: "invalid", tasks: [task("a")], maxConcurrent: 17).validated())
    }
    func testConcurrencyAndDependencyOrdering() throws {
        var run = try PlanRun(plan: .init(title: "build", tasks: [task("a"), task("b"), task("c", deps: ["a", "b"])], maxConcurrent: 2))
        XCTAssertEqual(run.schedule(now: Date()), ["a", "b"])
        XCTAssertEqual(run.schedule(now: Date()), [])
        run.finish("a", exitCode: 0, now: Date())
        XCTAssertEqual(run.schedule(now: Date()), [])
        run.finish("b", exitCode: 0, now: Date())
        XCTAssertEqual(run.schedule(now: Date()), ["c"])
        run.finish("c", exitCode: 0, now: Date())
        XCTAssertEqual(run.state, .succeeded)
    }
    func testFailureSkipsDependentsAndRunsRecoveryAndIndependentWork() throws {
        var run = try PlanRun(plan: .init(title: "failure", tasks: [task("a"), task("skip", deps: ["a"]), task("chain", deps: ["skip"]), task("recover", deps: ["a"], condition: .failure), task("cleanup", deps: ["chain"], condition: .completion), task("independent")], maxConcurrent: 1))
        XCTAssertEqual(run.schedule(now: Date()), ["a"])
        run.finish("a", exitCode: 7, now: Date())
        XCTAssertEqual(run.schedule(now: Date()), ["recover"])
        XCTAssertEqual(run.tasks.first { $0.id == "chain" }?.state, .skipped)
        run.finish("recover", exitCode: 0, now: Date())
        XCTAssertEqual(run.schedule(now: Date()), ["cleanup"])
        run.finish("cleanup", exitCode: 0, now: Date())
        XCTAssertEqual(run.schedule(now: Date()), ["independent"])
        run.finish("independent", exitCode: 0, now: Date())
        XCTAssertEqual(run.state, .failed)
    }
    func testCancelDrainsRunningCommandsWithoutStartingMore() throws {
        var run = try PlanRun(plan: .init(title: "cancel", tasks: [task("a"), task("b")]))
        XCTAssertEqual(run.schedule(now: Date()), ["a"])
        run.cancel(now: Date())
        XCTAssertEqual(run.state, .cancelling)
        XCTAssertEqual(run.schedule(now: Date()), [])
        run.finish("a", exitCode: 0, now: Date())
        XCTAssertEqual(run.state, .cancelled)
        XCTAssertEqual(run.tasks.last?.state, .skipped)
    }
    func testRecoveryNeverReplaysOrClaimsSuccess() throws {
        var run = try PlanRun(plan: .init(title: "restart", tasks: [task("a"), task("b")]))
        _ = run.schedule(now: Date())
        run.recover(now: Date())
        XCTAssertEqual(run.state, .lost)
        XCTAssertEqual(run.schedule(now: Date()), [])
        XCTAssertTrue(run.tasks.allSatisfy { $0.state == .lost })
        run.finish("a", exitCode: 0, now: Date())
        XCTAssertEqual(run.state, .lost)
    }
}
