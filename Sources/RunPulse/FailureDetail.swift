import Foundation

// File-scope types (not nested) to stay within SwiftLint's `nesting` rule.
private struct JobStep: Decodable {
    var name: String
    var conclusion: String?
}

private struct Job: Decodable {
    var name: String
    var conclusion: String?
    var steps: [JobStep]?
}

private struct JobsPage: Decodable {
    var jobs: [Job]
}

enum FailureDetail {
    /// First failed job of the run and its first failed step.
    static func parse(_ data: Data) -> FailedStep? {
        guard let page = try? JSONDecoder().decode(JobsPage.self, from: data),
              let job = page.jobs.first(where: { Run.failureConclusions.contains($0.conclusion ?? "") })
        else { return nil }
        let step = job.steps?.first { Run.failureConclusions.contains($0.conclusion ?? "") }
        return FailedStep(job: job.name, step: step?.name)
    }
}
