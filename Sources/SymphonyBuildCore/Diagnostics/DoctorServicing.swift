import Foundation

public protocol DoctorServicing {
    func makeReport(from request: DoctorCommandRequest) throws -> DiagnosticsReport
    func render(report: DiagnosticsReport, json: Bool, quiet: Bool) throws -> String
}

