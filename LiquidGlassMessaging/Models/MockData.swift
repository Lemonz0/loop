import Foundation

public enum MockData {
    public static func snapshot(now: Date = .now) -> CircleSnapshot {
        let users = [User(id: "me", name: "You", allowsTrollPosts: true),
                     User(id: "maya", name: "Maya", allowsTrollPosts: true),
                     User(id: "dan", name: "Dan", allowsTrollPosts: true),
                     User(id: "ioana", name: "Ioana", allowsTrollPosts: true),
                     User(id: "alex", name: "Alex", allowsTrollPosts: false)]
        let media = [1018, 1015, 1025, 1003].map { CircleMedia(url: URL(string: "https://picsum.photos/id/\($0)/900/1200")) }
        let posts = [Post(id: UUID(), author: users[1], media: [media[0], media[1]],
                          caption: "Sunset at the lake, you all missed out.", createdAt: now.addingTimeInterval(-7200),
                          likes: 12, comments: ["Next time, invite us!", "That light.", "Our spot.", "See you tomorrow."], isLiked: false),
                     Post(id: UUID(), author: users[2], media: [media[1]], caption: "A little escape with the circle.",
                          createdAt: now.addingTimeInterval(-18000), likes: 7, comments: [], isLiked: false)]
        let stories = (1...4).map { i in
            Story(id: UUID(), user: users[i], media: media[i-1], caption: i == 1 ? posts[0].caption : "A moment from today.",
                  createdAt: now.addingTimeInterval(-Double([3, 9, 21, 23][i-1]) * 3600),
                  expiresAt: now.addingTimeInterval(Double([21, 15, 3, 1][i-1]) * 3600), isSeen: i == 3, isLiked: false)
        }
        let trolls = (0..<4).map { i in
            TrollPost(id: UUID(), imageURL: media[i].url, caption: ["Caught in the moment.", "No context needed.", "The usual suspects.", "A classic."][i],
                      createdAt: now.addingTimeInterval(-Double(i+1) * 1800), reactions: [8, 11, 3, 5][i],
                      hasReacted: false, aspectRatio: [0.76, 1.14, 1.08, 0.73][i])
        }
        return CircleSnapshot(friends: users, posts: posts, stories: stories, trollPosts: trolls)
    }
}
