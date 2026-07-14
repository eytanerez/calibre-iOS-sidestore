import SwiftUI

// MARK: - Anchoring

/// Collects the frames of controls tagged with `.tutorialAnchor(_:)` so the
/// overlay can spotlight the *real* on-screen element wherever it lands.
struct TutorialAnchorPreference: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// Tags this control so a tutorial step can spotlight it by `id`.
    func tutorialAnchor(_ id: String) -> some View {
        anchorPreference(key: TutorialAnchorPreference.self, value: .bounds) { [id: $0] }
    }

    /// Hosts a hands-on tutorial layer above this view. Apply at the screen
    /// root, below the tagged controls, so their anchors are visible.
    func tutorialOverlay(_ controller: TutorialController) -> some View {
        modifier(TutorialOverlayModifier(controller: controller))
    }
}

// MARK: - Overlay host

struct TutorialOverlayModifier: ViewModifier {
    let controller: TutorialController

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TutorialAnchorPreference.self) { anchors in
                GeometryReader { proxy in
                    if let step = controller.currentStep {
                        TutorialScrim(
                            step: step,
                            position: controller.position,
                            targetRect: step.anchor
                                .flatMap { anchors[$0] }
                                .map { proxy[$0] },
                            containerSize: proxy.size,
                            controller: controller
                        )
                        .ignoresSafeArea()
                    }
                }
                .ignoresSafeArea()
            }
            .animation(Motion.easeMedium, value: controller.activeIndex)
    }
}

// MARK: - Scrim

/// The dimmed layer with a hole cut around the spotlit control, the looping
/// hint, and the coaching card. Touches pass through the hole to the real
/// control; touches elsewhere are blocked (or advance concept steps).
struct TutorialScrim: View {
    let step: TutorialStep
    let position: (step: Int, total: Int)?
    let targetRect: CGRect?
    let containerSize: CGSize
    let controller: TutorialController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Padded (and, for circles, squared) target rect in overlay coordinates.
    private var spotRect: CGRect? {
        guard let target = targetRect else { return nil }
        let padded = target.insetBy(dx: -step.cutoutPadding, dy: -step.cutoutPadding)
        guard case .circle = step.cutout else { return padded }
        let side = max(padded.width, padded.height)
        return CGRect(x: padded.midX - side / 2, y: padded.midY - side / 2, width: side, height: side)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimLayer
            interactionLayer
            if let rect = spotRect {
                TutorialSpotlightRing(rect: rect, cutout: step.cutout)
                if step.hint != .none {
                    TutorialHintView(hint: step.hint, rect: rect)
                        .id(step.id)
                }
            }
            coachLayer
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
    }

    // MARK: Dim

    private var dimLayer: some View {
        // Bleed the outer rect well past the edges so the dim covers the
        // safe-area strips; the hole is cut with the even-odd rule.
        let outer = CGRect(
            x: -200, y: -200,
            width: containerSize.width + 400, height: containerSize.height + 400
        )
        return Path { path in
            path.addRect(outer)
            if let rect = spotRect { addCutout(&path, rect) }
        }
        .fill(Color.calibre.shadowTint.opacity(0.62), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func addCutout(_ path: inout Path, _ rect: CGRect) {
        switch step.cutout {
        case .circle:
            path.addEllipse(in: rect)
        case .capsule:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
        case .roundedRect(let radius):
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        case .rect:
            path.addRect(rect)
        }
    }

    // MARK: Interaction

    @ViewBuilder private var interactionLayer: some View {
        switch step.advance {
        case .tapToContinue:
            // A tap anywhere on the dimmed area moves the concept beat along.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { controller.advance() }
        case .perform:
            // Block strays around the control; leave the hole open so the
            // real gesture/tap lands on the real control beneath.
            if let rect = spotRect {
                TutorialBlockerPanes(hole: rect, container: containerSize)
            }
        }
    }

    // MARK: Coach card

    private var coachLayer: some View {
        VStack(spacing: 0) {
            if spotRect == nil {
                Spacer(minLength: 0)
                card
                Spacer(minLength: 0)
            } else if cardTowardTop {
                card
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                card
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.xxl)
    }

    private var card: some View {
        TutorialCoachCard(step: step, position: position, controller: controller)
            .id(step.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
    }

    /// Put the card opposite the target: control low on screen → card up top.
    private var cardTowardTop: Bool {
        guard let rect = spotRect else { return false }
        return rect.midY > containerSize.height * 0.52
    }
}

// MARK: - Passthrough blockers

/// Four clear panes surrounding the hole. They capture stray taps (so the
/// user can't wander off mid-lesson) while leaving the hole itself open for
/// the real control to receive the actual gesture.
struct TutorialBlockerPanes: View {
    let hole: CGRect
    let container: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            pane(CGRect(x: 0, y: 0, width: container.width, height: max(0, hole.minY)))
            pane(CGRect(x: 0, y: hole.maxY, width: container.width, height: max(0, container.height - hole.maxY)))
            pane(CGRect(x: 0, y: hole.minY, width: max(0, hole.minX), height: hole.height))
            pane(CGRect(x: hole.maxX, y: hole.minY, width: max(0, container.width - hole.maxX), height: hole.height))
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
    }

    private func pane(_ rect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture { Haptics.shared.play(.selection) }
    }
}

// MARK: - Coach card

struct TutorialCoachCard: View {
    let step: TutorialStep
    let position: (step: Int, total: Int)?
    let controller: TutorialController

    private var isLast: Bool { position.map { $0.step == $0.total } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                if let position {
                    Eyebrow("Tip \(position.step) of \(position.total)")
                }
                Spacer()
                Button("Skip") { controller.skip() }
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Ends this walkthrough and won't show it again")
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(step.title)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.message)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow
        }
        .frame(maxWidth: 380, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .calibreShadow(.modal)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actionRow: some View {
        switch step.advance {
        case .tapToContinue:
            Button {
                controller.advance()
            } label: {
                Text(isLast ? "Got it" : "Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
        case .perform:
            if let prompt = step.actionPrompt {
                HStack(spacing: Space.s) {
                    Image(systemName: promptSymbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(prompt)
                        .font(CalibreType.bodySemiBold)
                }
                .foregroundStyle(Color.calibre.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isSummaryElement)
            }
        }
    }

    private var promptSymbol: String {
        switch step.hint {
        case .swipe, .drag: "hand.draw"
        case .longPress: "hand.tap.fill"
        case .type: "keyboard"
        default: "hand.tap"
        }
    }
}
