import SwiftUI

struct ChatWorkspaceView: View {
    let model: AppModel

    var body: some View {
        if model.selectedChannel?.kind == .voice {
            VoiceChannelView(model: model)
        } else {
            HStack(spacing: 0) {
                ChatDetailView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.showInspector {
                    Divider()
                    MemberInspectorView(
                        sections: model.memberSections,
                        selectedMemberID: model.selectedMember?.id,
                        isProfilePresented: model.isInspectorProfilePresented,
                        profile: model.selectedProfile,
                        isLoadingProfile: model.isLoadingProfile,
                        profileErrorMessage: model.profileErrorMessage,
                        selectMember: model.selectMember,
                        dismissProfile: model.dismissProfile
                    )
                    .frame(width: ChatChromeMetrics.memberListWidth)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
