import SwiftUI

struct AccountInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthSessionManager.shared
    @State private var code = ""
    @State private var generated: AccountInvite?
    @State private var working = false
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientGlowBackground()
                ScrollView {
                    GlassEffectContainer(spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Join a circle").font(.title2.bold())
                            SecureField("Invite code", text: $code).padding().circleSurface(radius: 20)
                            Button("Join") {
                                working = true
                                Task { if await auth.joinCircle(code: code) { dismiss() }; working = false }
                            }.buttonStyle(.glassProminent).disabled(code.isEmpty || working)
                            Text("Invite a friend").font(.title2.bold()).padding(.top)
                            ForEach(auth.circles.filter { $0.ownerId == auth.currentSession?.user.id }) { circle in
                                Button("Create invite for \(circle.name)") {
                                    working = true
                                    Task { generated = await auth.createInvite(circleID: circle.id); working = false }
                                }.buttonStyle(.glass).disabled(working).frame(minHeight: 44)
                            }
                            if let generated {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("One use · expires \(generated.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote)
                                    Text(generated.code).font(.callout.monospaced()).textSelection(.enabled)
                                    ShareLink(item: generated.code) { Label("Share invite", systemImage: "square.and.arrow.up") }.buttonStyle(.glass)
                                }.padding().circleSurface(radius: 20)
                            }
                            if let error = auth.lastError { Text(error).font(.footnote) }
                        }.padding(20)
                    }
                }
            }.navigationTitle("Circle invitations")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
#Preview("Invitations · dark") { AccountInviteView().circlePreviewTheme(.aurora) }
#Preview("Invitations · light") { AccountInviteView().circlePreviewTheme(.daylight) }
