import SwiftUI

struct ChatWorkspaceView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ChatDetailView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.showInspector {
                Divider()
                MemberInspectorView(
                    sections: model.memberSections,
                    selectedMemberID: model.selectedMember?.id,
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
    }
}
