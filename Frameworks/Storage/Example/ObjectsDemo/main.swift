//
//  main.swift
//  ConversationDemo
//
//  Created by 秋星桥 on 1/21/25.
//

import Storage

var db: Storage! = try Storage.db()

Demo.main()

struct Demo: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HStack(spacing: 16) {
                    NavigationLink {
                        Text("1")
                    } label: {
                        GiantButton(title: "Conversation DB")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        Text("1")
                    } label: {
                        GiantButton(title: "Message DB")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        Text("1")
                    } label: {
                        GiantButton(title: "Attachment DB")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        Text("1")
                    } label: {
                        GiantButton(title: "Model DB")
                    }
                    .buttonStyle(.plain)
                }
                .toolbar {
                    Button("Open Database") {
                        NSWorkspace.shared.open(db.databaseLocation)
                    }
                    Button("Reset Database") {
                        let location = db.databaseDir
                        db = nil
                        try? FileManager.default.removeItem(at: location)
                        exit(0)
                    }
                }
                .navigationTitle("Conversation Database")
            }
        }
    }

    struct GiantButton: View {
        let title: String
        var body: some View {
            RoundedRectangle(cornerRadius: 16)
                .foregroundStyle(.accent)
                .opacity(0.1)
                .frame(width: 128, height: 128, alignment: .center)
                .overlay {
                    Text(title)
                }
        }
    }
}
