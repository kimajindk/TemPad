import SwiftUI

struct MeasurementInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("아기의 움직임을 따라\n온도의 흐름을 살펴보세요")
                            .font(.system(size: 28, weight: .semibold))
                            .tracking(-0.8)
                        Text("TemPad는 자세와 의복, 접촉 조건을 고려한 보정 온도를 제공하도록 설계되었습니다.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                            .lineSpacing(8)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        explanation("보정 온도", text: "패드에 닿는 부위의 온도를 바탕으로 자세와 의복 등 측정 조건을 반영하는 방식입니다. 부위별 온도와 시간에 따른 변화를 함께 살펴볼 수 있습니다.")
                        Divider().overlay(Palette.line)
                        explanation("머리 영역 · 몸통 영역", text: "기본 화면은 두 영역의 온도 흐름을 보여줍니다. 머리는 뒤통수 등, 몸통은 등이나 가슴 등 현재 자세에서 패드에 닿는 면을 기준으로 살펴봅니다. 홈의 대표값은 두 영역 중 높은 온도입니다.")
                    }
                    .padding(24)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 24))

                    explanation("체온 확인이 필요할 때", text: "보정 온도와 임상적 체온 확인은 별개이므로, 확인이 필요할 때는 아기의 나이와 체온계 사용법에 맞는 방법으로 측정해 주세요.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("참고 자료")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        sourceLink("RCH · 신생아 피부 온도 관리", url: "https://www.rch.org.au/rchcpg/hospital_clinical_guideline_index/Thermoregulation_in_the_preterm_infant/")
                        sourceLink("미국소아과학회 · 아이의 체온 측정", url: "https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/How-to-Take-a-Childs-Temperature.aspx")
                        sourceLink("NHS · 아기의 체온 측정", url: "https://www.nhs.uk/baby/health/how-to-take-your-babys-temperature/")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.cream)
            .foregroundStyle(Palette.ink)
            .navigationTitle("측정 방식 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Palette.wine)
                        .accessibilityIdentifier("dismissMeasurementInfo")
                }
            }
        }
        .accessibilityIdentifier("measurementInfo")
    }

    private func explanation(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .lineSpacing(8)
        }
    }

    private func sourceLink(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.wine)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
        }
    }
}
