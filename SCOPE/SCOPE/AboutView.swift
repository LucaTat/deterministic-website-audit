import SwiftUI

struct AboutView: View {
    private let maxWidth: CGFloat = 480

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                VStack(spacing: 6) {
                    Text("About SCOPE")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Deterministic Website Audit")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("What it is")
                    Text("SCOPE is a client‑safe audit workflow designed for clear decisions. It runs deterministic checks and packages results into deliverables you can confidently send.")
                        .font(.body)

                    sectionTitle("Deterministic by design")
                    bulletList([
                        "Repeatable outputs for the same inputs.",
                        "No hidden randomness or model drift.",
                        "Operator‑controlled runs with explicit inputs."
                    ])

                    sectionTitle("What it is not")
                    bulletList([
                        "Not a full penetration test.",
                        "Not a replacement for product analytics.",
                        "Not a subjective design critique."
                    ])

                    sectionTitle("Outputs")
                    bulletList([
                        "Website Audit PDF",
                        "Decision Brief PDF / TXT",
                        "Evidence folder"
                    ])
                }
                .frame(maxWidth: maxWidth, alignment: .leading)

                Divider()

                Text(versionString())
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.primary)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(item)
                        .font(.body)
                }
            }
        }
    }

    private func versionString() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
