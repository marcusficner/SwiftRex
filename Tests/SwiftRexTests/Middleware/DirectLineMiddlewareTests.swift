@testable import SwiftRex
import XCTest

class DirectLineMiddlewareTests: MiddlewareTestsBase {
    func testDirectLineMiddlewareAction() {
        // Given
        let sut = DirectLineMiddleware<TestState>()

        let middlewareContext = MiddlewareContextMock()
        sut.context = { middlewareContext.value }
        let state = TestState()
        let getState = { state }
        let action = ActionReference()
        let lastInChainWasCalledExpectation = self.expectation(description: "last in chain was called")
        let lastInChain = lastActionInChain(action, state: state, expectation: lastInChainWasCalledExpectation)

        // Then
        sut.handle(action: action, getState: getState, next: lastInChain)

        // Expect
        wait(for: [lastInChainWasCalledExpectation], timeout: 3)
        XCTAssertEqual(0, middlewareContext.actionHandlerMock.actions.count)
    }

    func testDirectLineMiddlewareEvent() {
        // Given
        let sut = DirectLineMiddleware<TestState>()

        let middlewareContext = MiddlewareContextMock()
        sut.context = { middlewareContext.value }
        let state = TestState()
        let getState = { state }
        let event = EventReference()
        let lastInChainWasCalledExpectation = self.expectation(description: "last in chain was called")
        let lastInChain = lastEventInChain(event, state: state, expectation: lastInChainWasCalledExpectation)

        // Then
        sut.handle(event: event, getState: getState, next: lastInChain)

        // Expect
        wait(for: [lastInChainWasCalledExpectation], timeout: 3)
        XCTAssertEqual(0, middlewareContext.actionHandlerMock.actions.count)
    }

    func testDirectLineMiddlewareEventThatIsAnAction() {
        // Given
        let sut = DirectLineMiddleware<TestState>()

        let middlewareContext = MiddlewareContextMock()
        sut.context = { middlewareContext.value }
        let state = TestState()
        let getState = { state }
        let event = EventAndActionReference()
        let lastInChainWasCalledExpectation = self.expectation(description: "last in chain was called")
        let lastInChain = lastEventInChain(event, state: state, expectation: lastInChainWasCalledExpectation)

        // Then
        sut.handle(event: event, getState: getState, next: lastInChain)

        // Expect
        wait(for: [lastInChainWasCalledExpectation], timeout: 3)
        XCTAssertEqual(1, middlewareContext.actionHandlerMock.actions.count)
        XCTAssert((middlewareContext.actionHandlerMock.actions.first as! EventAndActionReference) === event)
    }
}
