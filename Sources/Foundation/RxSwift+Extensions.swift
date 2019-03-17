import RxSwift

public typealias ObservableSignal<T> = Observable<T>
public typealias FailableObservableSignal<T> = Observable<T>
public typealias ObservableSignalProducer<T> = Observable<T>
public typealias FailableObservableSignalProducer<T> = Observable<T>
public typealias SubscriptionOwner = DisposeBag
public typealias ObservableProperty = ObservableType
public typealias ReactiveProperty<T> = BehaviorSubject<T>

func reactiveProperty<T>(initialValue: T) -> ReactiveProperty<T> {
    return BehaviorSubject(value: initialValue)
}

extension Observable {
    func subscribe(onSuccess: @escaping (Element) -> Void,
                   onFailure: @escaping (Error) -> Void,
                   disposeBy subscriptionOwner: SubscriptionOwner) {
        subscribe(onNext: onSuccess, onError: onFailure).disposed(by: subscriptionOwner)
    }
}

extension StateProvider {
    /// The elements in the ObservableType sequence, which is expected to be the `StateType` (the app global state)
    public typealias StateType = E
}

extension StoreBase {
    public typealias E = State // swiftlint:disable:this type_name

    /**
     Because `StoreBase` is a `StateProvider`, it exposes a way for an `UIViewController` or other interested classes to subscribe to `State` changes.

     By default, this observation will have the following characteristics:
     - Hot observable, no observation side-effect
     - Replays the last (or initial) state
     - Never completes
     - Never fails
     - Observes on the `MainScheduler`

     Internally it maps to a `BehaviorSubject<StateType>`.

     - Parameter observer: the action to be managed by this store and handled by its middlewares and reducers
     - Returns: Subscription for `observer` that should be kept in a `disposeBag` for the same lifetime as its observer.
     */
    public func subscribe<O>(_ observer: O) -> Disposable where O: ObserverType, O.E == StateType {
        return state
            .observeOn(MainScheduler.instance)
            .subscribe(observer)
    }
}
