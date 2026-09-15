import XCTest
@testable import LabelCore

final class LabelOrderPlanTests: XCTestCase {
    let a = LabelOrderPlan.Label(sourcePage: 1, region: 0)
    let b = LabelOrderPlan.Label(sourcePage: 1, region: 1)
    let c = LabelOrderPlan.Label(sourcePage: 2, region: 0)
    func testCollated() throws {
        XCTAssertEqual(try LabelOrderPlan.make(labels: [a,b,c],copyPolicy: .engine(copies: 2,collated: true)),[a,b,c,a,b,c])
    }
    func testUncollated() throws {
        XCTAssertEqual(try LabelOrderPlan.make(labels: [a,b,c],copyPolicy: .engine(copies: 2,collated: false)),[a,a,b,b,c,c])
    }
    func testRangeBeforeCopies() throws {
        XCTAssertEqual(try LabelOrderPlan.make(labels: [a,b,c],selectedSourcePages: [2],copyPolicy: .engine(copies: 2,collated: true)),[c,c])
    }
    func testAlreadyExpandedPreservesDuplicates() throws {
        XCTAssertEqual(try LabelOrderPlan.make(labels: [a,a,b,b],copyPolicy: .alreadyExpanded),[a,a,b,b])
    }
    func testRejectsInvalidSelection() {
        XCTAssertThrowsError(try LabelOrderPlan.make(labels: [a],selectedSourcePages: [2],copyPolicy: .alreadyExpanded))
    }
    func testRejectsInvalidLabelsCopiesLimits() {
        XCTAssertThrowsError(try LabelOrderPlan.make(labels: [.init(sourcePage: 0,region: 0)],copyPolicy: .alreadyExpanded))
        XCTAssertThrowsError(try LabelOrderPlan.make(labels: [a],copyPolicy: .engine(copies: 0,collated: true)))
        XCTAssertThrowsError(try LabelOrderPlan.make(labels: [a],copyPolicy: .alreadyExpanded,maxOutputLabels: 0))
    }
    func testOverflowAndCap() {
        XCTAssertThrowsError(try LabelOrderPlan.make(labels: [a,b],copyPolicy: .engine(copies: Int.max,collated: true)))
        XCTAssertThrowsError(try LabelOrderPlan.make(labels: [a,b],copyPolicy: .engine(copies: 2,collated: true),maxOutputLabels: 3))
    }
    func testEmptySelectionDoesNotLoopHugeCopies() throws {
        XCTAssertEqual(try LabelOrderPlan.make(labels: [a],selectedSourcePages: [],copyPolicy: .engine(copies: Int.max,collated: true)),[])
    }
}
