import SwiftUI

// Use the property wrapper so Command Line Tools builds don't need SwiftUI's State macro plugin.
typealias ViewState<Value> = SwiftUI.State<Value>
