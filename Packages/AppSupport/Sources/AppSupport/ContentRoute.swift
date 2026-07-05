public enum ContentRoute: Equatable { case welcome, setup, browser }

/// Pure routing decision for the document window's empty/populated states.
public func contentRoute(pagesEmpty: Bool, isCreating: Bool) -> ContentRoute {
    guard pagesEmpty else { return .browser }
    return isCreating ? .setup : .welcome
}
