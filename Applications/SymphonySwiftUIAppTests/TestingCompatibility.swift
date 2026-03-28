import Testing

func XCTAssertEqual<T: Equatable>(
  _ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T
) {
  do {
    #expect(try lhs() == rhs())
  } catch {
    Issue.record("XCTAssertEqual helper threw: \(error)")
  }
}

func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?) {
  do {
    #expect(try value() == nil)
  } catch {
    Issue.record("XCTAssertNil helper threw: \(error)")
  }
}

func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?) {
  do {
    #expect(try value() != nil)
  } catch {
    Issue.record("XCTAssertNotNil helper threw: \(error)")
  }
}

func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool) {
  do {
    #expect(try expression())
  } catch {
    Issue.record("XCTAssertTrue helper threw: \(error)")
  }
}

func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool) {
  do {
    #expect(!(try expression()))
  } catch {
    Issue.record("XCTAssertFalse helper threw: \(error)")
  }
}

func XCTFail(_ message: String = "") {
  Issue.record(message.isEmpty ? "XCTFail invoked." : "XCTFail invoked: \(message)")
}
