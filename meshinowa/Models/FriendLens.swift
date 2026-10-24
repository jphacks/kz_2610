import Foundation

struct FriendLens {
    enum Mode: String, CaseIterable, Identifiable {
        case allFriends
        case favoriteFriends
        case selectedFriends

        var id: String { rawValue }
        var title: String {
            switch self {
            case .allFriends: return "友達全員"
            case .favoriteFriends: return "お気に入りの友達"
            case .selectedFriends: return "選択した友達"
            }
        }
    }

    var mode: Mode = .allFriends
    var selectedFriendIDs: Set<String> = []

    func includedFriendIDs(friends: [DemoFriend], favorites: Set<String>) -> Set<String> {
        let knownIDs = Set(friends.map(\.id))
        switch mode {
        case .allFriends: return knownIDs
        case .favoriteFriends: return knownIDs.intersection(favorites)
        case .selectedFriends: return knownIDs.intersection(selectedFriendIDs)
        }
    }
}
