#if canImport(Combine)
import Combine
import Foundation
import SwiftRex

/// An `EffectMiddleware` with no dependencies (Void) and having Input and Output Actions as the same type (`SymmetricalEffectMiddleware`).
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public typealias SimpleEffectMiddleware<Action, State> = EffectMiddleware<Action, Action, State, Void>

/// An `EffectMiddleware` having Input and Output Actions as the same type.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public typealias SymmetricalEffectMiddleware<Action, State, Dependencies> = EffectMiddleware<Action, Action, State, Dependencies>

/// Easiest way to implement a `Middleware`, with a single function that gives you all you need, and from which you can return an `Effect`.
///
/// A `MiddlewareEffect` is a function providing an incoming `Action`, `State` and `Context` (dispatcher source, dependencies, cancellation closure)
/// and expecting as result one or multiple effects that will eventually result in outgoing actions.
///
/// An `Effect` is a publisher or observable type according to your reactive framework. It can be a one-shot effect, such as an HTTP request,
/// an observation that gives back multiple values over time, such as CoreLocation or NotificationCenter, a Timer, a pure value already known
/// or even an empty effect using the `.doNothing` constructor, if there's no need for side-effects.
/// `Effect` cannot fail, and its element/output/value type is the `OutputAction` generic of this middleware. The purpose is running tasks,
/// creating actions as they respond and returning these actions over time back to the Store. When the Effect completes, it should send a
/// completion event so the middleware will cleanup the resources.
///
/// Cancellation: effects can optionally provide a cancellation token, which can be any hashable value. If another effect arrives in the same
/// middleware instance having the very same cancellation token, the previous effect will be cancelled and replaced by the new one. This is
/// useful in case you want to keep only the last request of certain kind running, but cancel any previous ongoing request when a new is
/// dispatched. You can also explicitly cancel one or many effects at any point. For that, you will be given a `toCancel` closure during every
/// action arrival within the `Context` (third parameter). Feel free to call cancellation at that point or even later, if you hold this `toCancel`
/// closure.
///
/// Examples
///
/// Using Promises
/// ```
/// let someMiddleware = EffectMiddleware<ApiRequestAction, ApiResponseAction, SomeState, Void>.onAction { action, state, context in
///   switch action {
///   case .users:
///     return .promise { completion in
///       DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
///         completion(ApiResponseAction.someResponse("42"))
///       }
///     }
///   case .somethingIDontCare:
///     return .doNothing
///   }
/// }
/// ```
///
/// From Publisher
/// ```
/// typealias ApiFetchMiddlewareDependencies = (session: @escaping () -> URLSession, decoder: @escaping () -> JSONDecoder)
///
/// let apiFetchMiddleware =
///   EffectMiddleware<ApiRequestAction, ApiResponseAction, SomeState, ApiFetchMiddlewareDependencies>.onAction { action, state, context in
///     switch action {
///     case .users:
///       return context.dependencies.urlSession
///         .dataTaskPublisher(for: fetchAllUsersURL())
///         .map { data, _ in data }
///         .decode(type: [User].self, decoder: context.dependencies)
///         .map { users in ApiResponseAction.gotUserList(users) }
///         .replaceError(with: ApiResponseAction.errorRetrivingUserList)
///         .asEffect
///     case .user(id: UUID):
///       // ..
///     case .somethingIDontCare:
///       return .doNothing
///     }
///   }.inject((session: { URLSession.shared }, decoder: JSONDecoder.init))
/// ```
///
/// Cancellation
/// ```
/// typealias ApiFetchMiddlewareDependencies = (session: @escaping () -> URLSession, decoder: @escaping () -> JSONDecoder)
///
/// let apiFetchMiddleware =
///   EffectMiddleware<ApiRequestAction, ApiResponseAction, SomeState, ApiFetchMiddlewareDependencies>.onAction { action, state, context in
///     switch action {
///     case let .userPicture(userId):
///       return context.dependencies.urlSession
///         .dataTaskPublisher(for: fetchPicture())
///         .map { data, _ in ApiResponseAction.gotUserPicture(id: userId, data: data) }
///         .replaceError(with: ApiResponseAction.errorRetrivingUserPicture(id: userId))
///         .asEffect(cancellationToken: "image-for-user-\(userId)") // this will automatically cancel any pending download for the same image
///                                                                  // using the URL would also be possible
///     case let .cancelImageDownload(userId):
///       return context.toCancel("image-for-user-\(userId)")        // alternatively you can explicitly cancel tasks by token
///     }
///   }.inject((session: { URLSession.shared }, decoder: JSONDecoder.init))
/// ```
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class EffectMiddleware<InputActionType, OutputActionType, StateType, Dependencies>: MiddlewareProtocol {
    var cancellables = [Int: AnyCancellable]()
    private var cancellableButNotViaToken = Set<AnyCancellable>()
    private var actionHandler: (InputActionType, ActionSource, @escaping GetState<StateType>) -> IO<OutputActionType>
    let dependencies: Dependencies

    init(
        dependencies: Dependencies,
        onAction: @escaping (InputActionType, ActionSource, @escaping GetState<StateType>) -> Effect<Dependencies, OutputActionType>
    ) {
        self.dependencies = dependencies
        self.actionHandler = { _, _, _ in .pure() }
        self.actionHandler = { action, dispatcher, state in
            IO { [weak self] output in
                guard let self = self else { return }

                let effect = onAction(action, dispatcher, state)
                self.runOptionalEffect(effect, output: output)
            }
        }
    }

    init(
        dependencies: Dependencies,
        actionHandler: @escaping (InputActionType, ActionSource, @escaping GetState<StateType>) -> IO<OutputActionType>
    ) {
        self.dependencies = dependencies
        self.actionHandler = actionHandler
    }

    public func handle(action: InputActionType, from dispatcher: ActionSource, state: @escaping GetState<StateType>) -> IO<OutputActionType> {
        actionHandler(action, dispatcher, state)
    }

    func runOptionalEffect(_ effect: Effect<Dependencies, OutputActionType>, output: AnyActionHandler<OutputActionType>) {
        guard effect.doesSomething else { return }

        let cancelTokenPublisher: (AnyHashable) -> Void = { [weak self] cancellingToken in
            guard let self = self, let effect = self.cancellables[cancellingToken.hashValue] else {
                #if DEBUG && SWIFTREX_DEBUG
                print("⚠️ Can't cancel Effect with token \(cancellingToken.hashValue) because it was not found in the dictionary with keys " +
                      "\(self.cancellables.keys.joined(separator: ", ")).")
                #endif
                return
            }
            effect.cancel()
            self.cancellables.removeValue(forKey: cancellingToken.hashValue)
            #if DEBUG && SWIFTREX_DEBUG
            print("Cancelled Effect with token \(cancellingToken.hashValue).")
            #endif
        }

        let toCancel: (AnyHashable) -> FireAndForget<DispatchedAction<OutputActionType>> = { cancellingToken in
            FireAndForget(
                Empty<DispatchedAction<OutputActionType>, Never>()
                    // Combine `.receive(on:)` is eager, so if this is already running in the main queue, it happens immediately,
                    // otherwise it schedules to the next Main Thread RunLoop. This is important because cancellation is requested
                    // by the user (downstream) and must occur AS SOON AS POSSIBLE!
                    .receive(on: DispatchQueue.main)
                    .handleEvents(receiveSubscription: { _ in cancelTokenPublisher(cancellingToken) })
            )
        }

        guard let publisher = effect.run((dependencies: self.dependencies, toCancel: toCancel)) else { return }

        if let token = effect.token {
            let subscription = publisher
                .handleEvents(
                    receiveCompletion: { [weak self] _ in
                        // Completion, that means UPSTREAM finished sending actions, not cancellation from the downstream.
                        // That means, there's no urgency in cleaning up the `cancellables` dictionary, we can afford to
                        // do it in the next Main Thread RunLoop.
                        DispatchQueue.main.async {
                            self?.cancellables.removeValue(forKey: token.hashValue)
                        }
                    }
                )
                .sink { output.dispatch($0.action, from: $0.dispatcher) }
            self.cancellables[token.hashValue] = subscription
        } else {
            publisher
                .sink { output.dispatch($0.action, from: $0.dispatcher) }
                .store(in: &self.cancellableButNotViaToken)
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension EffectMiddleware {
    public static func onAction(
        do onAction: @escaping (InputActionType, ActionSource, @escaping GetState<StateType>) -> Effect<Dependencies, OutputActionType>
    ) -> MiddlewareReader<Dependencies, EffectMiddleware> {
        MiddlewareReader { dependencies in
            EffectMiddleware(dependencies: dependencies, onAction: onAction)
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension EffectMiddleware where Dependencies == Void {
    public static func onAction(
        do onAction: @escaping (InputActionType, ActionSource, @escaping GetState<StateType>) -> Effect<Dependencies, OutputActionType>
    ) -> EffectMiddleware<InputActionType, OutputActionType, StateType, Dependencies> {
        EffectMiddleware(dependencies: (), onAction: onAction)
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension EffectMiddleware: Semigroup {
    public static func <> (lhs: EffectMiddleware, rhs: EffectMiddleware) -> EffectMiddleware {
        EffectMiddleware(
            dependencies: lhs.dependencies,
            actionHandler: { action, dispatcher, getState in
                let io1 = lhs.handle(action: action, from: dispatcher, state: getState)
                let io2 = rhs.handle(action: action, from: dispatcher, state: getState)

                return io1 <> io2
            }
        )
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension EffectMiddleware: Monoid where Dependencies == Void {
    public static var identity: EffectMiddleware<InputActionType, OutputActionType, StateType, Dependencies> {
        Self.onAction { _, _, _ in .doNothing }
    }
}

#endif
