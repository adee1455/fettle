import XCTest
@testable import Fettle

@MainActor
final class JobManagerTests: XCTestCase {
    private var jobManager: JobManager!

    override func setUp() {
        super.setUp()
        jobManager = JobManager()
    }

    override func tearDown() {
        for job in jobManager.jobs {
            jobManager.cancel(job)
        }
        jobManager = nil
        super.tearDown()
    }

    private func makeDummyAction(id: String = "dummy") -> ConversionAction {
        ConversionAction(
            id: id,
            title: "Dummy Action",
            subtitle: "Test",
            systemImage: "gear",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        )
    }

    private func makeDummyItem() -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
    }

    func testEnqueueCreatesJobAndStarts() {
        let action = makeDummyAction()
        let item = makeDummyItem()

        let job = jobManager.enqueue(action: action, inputFiles: [item])
        XCTAssertEqual(jobManager.jobs.count, 1)
        XCTAssertEqual(job.action.id, action.id)
        XCTAssertTrue(job.status == .running || job.status == .queued)
    }

    func testCancelStopsRunningJob() async {
        let action = makeDummyAction()
        let item = makeDummyItem()

        let job = jobManager.enqueue(action: action, inputFiles: [item])
        XCTAssertEqual(job.status, .running)

        jobManager.cancel(job)
        XCTAssertEqual(job.status, .cancelled)
        XCTAssertEqual(job.statusMessage, "Cancelled")
    }

    func testClearFinishedRemovesFinishedJobs() {
        let action = makeDummyAction()
        let item = makeDummyItem()

        let job1 = jobManager.enqueue(action: action, inputFiles: [item])
        jobManager.cancel(job1) // Now .cancelled

        let job2 = Job(action: action, inputFiles: [item])
        job2.status = .completed
        jobManager.jobs.append(job2)

        let job3 = Job(action: action, inputFiles: [item])
        job3.status = .failed
        jobManager.jobs.append(job3)

        XCTAssertEqual(jobManager.jobs.count, 3)
        jobManager.clearFinished()
        XCTAssertEqual(jobManager.jobs.count, 0)
    }

    func testMaxConcurrencyRespected() {
        jobManager.maxConcurrentJobs = 2

        let action = makeDummyAction()
        let item = makeDummyItem()

        let j1 = jobManager.enqueue(action: action, inputFiles: [item])
        let j2 = jobManager.enqueue(action: action, inputFiles: [item])
        let j3 = jobManager.enqueue(action: action, inputFiles: [item])
        let j4 = jobManager.enqueue(action: action, inputFiles: [item])

        let running = jobManager.jobs.filter { $0.status == .running }.count
        let queued = jobManager.jobs.filter { $0.status == .queued }.count

        XCTAssertEqual(running, 2)
        XCTAssertEqual(queued, 2)

        // Cancel running jobs to stop tasks
        jobManager.cancel(j1)
        jobManager.cancel(j2)
        jobManager.cancel(j3)
        jobManager.cancel(j4)
    }

    func testRemoveJobCancelsAndDeletes() {
        let action = makeDummyAction()
        let item = makeDummyItem()

        let job = jobManager.enqueue(action: action, inputFiles: [item])
        XCTAssertEqual(jobManager.jobs.count, 1)

        jobManager.removeJob(job)
        XCTAssertEqual(jobManager.jobs.count, 0)
    }
}
