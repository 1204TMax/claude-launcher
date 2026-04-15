import SwiftUI

struct ProfilesWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    private let runtimeValueWidth: CGFloat = 168

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    profileTabs
                    if let profile = appModel.selectedProfile {
                        editor(profile)
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .launcherPanelBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Profiles")
                .font(.launcherTitle)
                .foregroundStyle(LauncherTheme.primaryText)
            Text("Manage reusable launch presets with the same minimal system.")
                .font(.launcherMeta)
                .foregroundStyle(LauncherTheme.secondaryText)
        }
    }

    private var profileTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appModel.profiles) { profile in
                    Button {
                        appModel.selectProfile(profile.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.launcherBody)
                                .foregroundStyle(LauncherTheme.primaryText)
                            Text(profile.workingDirectory)
                                .font(.launcherMini)
                                .foregroundStyle(LauncherTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(width: 180, alignment: .leading)
                        .background(appModel.selectedProfileID == profile.id ? Color.white : LauncherTheme.softFill.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(appModel.selectedProfileID == profile.id ? LauncherTheme.border.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: appModel.createProfile) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LauncherTheme.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LauncherTheme.border.opacity(0.8), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func editor(_ profile: LaunchProfile) -> some View {
        VStack(spacing: 16) {
            LauncherSurfaceCard(cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("Name")
                    textField(text: binding(profile, \.name), placeholder: "Profile name")

                    fieldLabel("Workspace")
                    HStack(spacing: 8) {
                        textField(text: binding(profile, \.workingDirectory), placeholder: "/path/to/project")
                        Button("Browse", action: appModel.browseWorkingDirectory)
                            .buttonStyle(LauncherGhostButtonStyle())
                    }

                    fieldLabel("Model")
                    compactMenu(
                        selection: binding(profile, \.model),
                        items: LaunchProfile.suggestedModels,
                        minWidth: runtimeValueWidth
                    ) { $0 }
                }
                .padding(16)
            }

            LauncherSurfaceCard(cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("Runtime")
                    runtimeRow(title: "Permission", value: profile.permissionMode.displayName)
                    runtimeRow(title: "Launch", value: profile.launchMode.displayName)
                    runtimeRow(title: "Reasoning", value: profile.thinkingDepth.displayName)

                    fieldLabel("Default Count")
                    textField(
                        text: Binding(
                            get: { String(profile.batchCount) },
                            set: { value in
                                if let count = Int(value.filter(\.isNumber)), count >= 1 {
                                    appModel.updateSelectedProfile { $0.batchCount = count }
                                }
                            }
                        ),
                        placeholder: "1"
                    )
                }
                .padding(16)
            }

            LauncherSurfaceCard(cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    fieldLabel("Additional Directories")
                    textField(
                        text: Binding(
                            get: { profile.additionalDirectories.joined(separator: ", ") },
                            set: { value in
                                appModel.updateSelectedProfile {
                                    $0.additionalDirectories = value
                                        .split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                }
                            }
                        ),
                        placeholder: "dir1, dir2"
                    )

                    fieldLabel("Rename Template")
                    textField(text: binding(profile, \.startupRenameTemplate), placeholder: "{{profile}} {{index}}")

                    fieldLabel("Startup Message")
                    textEditor(text: binding(profile, \.startupMessage), minHeight: 90)

                    fieldLabel("System Prompt")
                    textEditor(text: binding(profile, \.appendSystemPrompt), minHeight: 90)
                }
                .padding(16)
            }

            HStack(spacing: 10) {
                Button("Duplicate", action: appModel.duplicateSelectedProfile)
                    .buttonStyle(LauncherGhostButtonStyle())
                Button("Delete", role: .destructive, action: appModel.deleteSelectedProfile)
                    .buttonStyle(LauncherGhostButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        LauncherSurfaceCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No profile selected")
                    .font(.launcherBodyStrong)
                    .foregroundStyle(LauncherTheme.primaryText)
                Text("Create a new profile to configure launch defaults.")
                    .font(.launcherMeta)
                    .foregroundStyle(LauncherTheme.secondaryText)
            }
            .padding(16)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        LauncherSectionLabel(text: text)
    }

    private func runtimeRow(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.launcherBody)
                .foregroundStyle(LauncherTheme.primaryText)
            Spacer(minLength: 16)
            LauncherChip(text: value)
                .frame(width: runtimeValueWidth, alignment: .leading)
        }
    }

    private func textField(text: Binding<String>, placeholder: String) -> some View {
        LauncherTextFieldContainer {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.launcherBody)
                .foregroundStyle(LauncherTheme.primaryText)
                .tint(LauncherTheme.primaryText)
        }
    }

    private func textEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 14))
            .foregroundStyle(LauncherTheme.primaryText)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.85), lineWidth: 1)
            )
    }

    private func compactMenu<T: Hashable>(selection: Binding<T>, items: [T], minWidth: CGFloat, label: @escaping (T) -> String) -> some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button {
                    selection.wrappedValue = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection.wrappedValue == item ? "checkmark" : "")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 14)
                        Text(label(item))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.vertical, 3)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label(selection.wrappedValue))
                    .font(.launcherBody)
                    .foregroundStyle(LauncherTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondaryText)
            }
            .frame(minWidth: minWidth, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.95), lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
    }

    private func binding<Value>(_ profile: LaunchProfile, _ keyPath: WritableKeyPath<LaunchProfile, Value>) -> Binding<Value> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                appModel.updateSelectedProfile { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
