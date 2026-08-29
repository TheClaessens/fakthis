// THROWAWAY PROTOTYPE. Canned content so every surface is populated. Real density matters
// more than real data for the question this prototype answers.

import Foundation
import Fakthis

enum Fixtures {
    static let brainDump = """
        So the thing customers keep hitting — you add something to the basket on mobile, go \
        through to checkout, and the total shown is the old total, from before you added it. \
        Sarah on the Northbeam account sent it in this morning, that's the third time this \
        month. It fixes itself if you pull to refresh. I think the checkout page is just \
        trusting the number the basket page handed it instead of asking pricing again.
        """

    static let storyReply = GenerateReply(
        ticketType: .story,
        title: "As a shopper I want the checkout total to match my current basket "
            + "so that I never pay against a stale figure",
        shortLabel: "Stale checkout total",
        description: """
            **Northbeam** shoppers on mobile web see a checkout total carried over from before \
            their last basket change. The figure corrects itself on a manual refresh, so the \
            **basket** holds the right contents and the **checkout summary** is reading a total \
            it was handed rather than one it asked for. Support has taken this three times this \
            month, most recently from the Northbeam account team.

            The checkout summary should recalculate from the current basket on load, going to \
            the shared pricing service the same way the basket page does since FAK-198 moved \
            that call. Scope is the summary figure only; the payment step is untouched by this \
            Ticket.
            """,
        openQuestions: [
            "Does the stale total reach the payment step, or only the checkout summary?",
            "Should the recalculation run on every checkout load, or only when the basket "
                + "changed since the last render?",
        ]
    )

    static let storyDefinitionOfDone = [
        "The checkout summary recalculates its total from the current basket on page load",
        "A basket edited in another tab shows the corrected total on the checkout page",
        "The reported reproduction path no longer shows a stale figure on mobile web",
        "Mobile web and the iOS wrapper are both covered",
    ]

    static let issueTypes = [
        JiraIssueType(name: "Story", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Bug", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Task", hierarchyLevel: 0, subtask: false),
        JiraIssueType(name: "Epic", hierarchyLevel: 1, subtask: false),
        JiraIssueType(name: "Sub-task", hierarchyLevel: -1, subtask: true),
    ]

    static let epics = [
        CatalogEpic(key: TicketKey("FAK-100"), name: "Checkout", status: "In Progress"),
        CatalogEpic(key: TicketKey("FAK-140"), name: "Basket and pricing", status: "In Progress"),
        CatalogEpic(key: TicketKey("FAK-90"), name: "Mobile web", status: "In Progress"),
    ]

    static let rows: [CatalogRow] = [
        CatalogRow(
            key: TicketKey("FAK-231"),
            title: "As a shopper I want the checkout total to match my basket after an edit",
            jiraIssueType: "Story",
            labels: ["checkout"],
            parentEpicKey: TicketKey("FAK-100"),
            status: "In Progress",
            shortLabel: "Stale checkout total",
            ticketType: .story
        ),
        CatalogRow(
            key: TicketKey("FAK-198"),
            title: "Move basket total onto the shared pricing service",
            jiraIssueType: "Task",
            parentEpicKey: TicketKey("FAK-140"),
            status: "Done",
            shortLabel: "Basket total to pricing service",
            ticketType: .chore
        ),
        CatalogRow(
            key: TicketKey("FAK-311"),
            title: "Pricing service returns 0 for gift cards",
            jiraIssueType: "Bug",
            parentEpicKey: TicketKey("FAK-140"),
            status: "In Review"
        ),
        CatalogRow(
            key: TicketKey("FAK-274"),
            title: "Checkout summary redesign",
            jiraIssueType: "Story",
            parentEpicKey: TicketKey("FAK-100"),
            status: "To Do"
        ),
    ]

    // Chat transcript. Session persists a transcript but does not expose one on State, so the
    // prototype holds its own. FAKED IN THE PROTOTYPE LAYER.
    static let chat: [ChatTurn] = [
        .init(role: .agent, text: "Does the stale total reach the payment step, or only the "
            + "checkout summary?"),
        .init(role: .pm, text: "Only the summary as far as we know. Sarah never got as far as "
            + "paying — she spotted the number and stopped."),
        .init(role: .agent, text: "Should the recalculation run on every checkout load, or only "
            + "when the basket changed since the last render?"),
    ]

    static let material: [MaterialRow] = [
        .init(name: "northbeam-support-thread.txt", kind: .text, note: "distilled into the description"),
        .init(name: "checkout-stale-total.png", kind: .screenshot, note: "sent to the model"),
        .init(name: "repro-mobile-safari.mov", kind: .video, note: "not sent to the model · 84 MB"),
    ]

    // §11 Batch. FAKED IN THE PROTOTYPE LAYER — State has no Batch (ticket #27).
    static let batchName = "Checkout totals"

    static let batchDrafts: [BatchDraft] = [
        .init(
            shortLabel: "Stale checkout total",
            ticketType: .story,
            epic: "FAK-100 Checkout",
            openQuestionCount: 2,
            title: storyReply.title,
            description: storyReply.description
        ),
        .init(
            shortLabel: "Recalculate on basket change",
            ticketType: .chore,
            epic: "FAK-140 Basket and pricing",
            openQuestionCount: 0,
            title: "Recalculate the checkout total when the basket changes",
            description: """
                The checkout summary currently reads a total handed to it by the basket page. \
                Have it call the shared **pricing service** on load and on any basket change \
                event, so the figure it shows is always the one pricing would return.
                """
        ),
        .init(
            shortLabel: "Telemetry for stale totals",
            ticketType: .chore,
            epic: "FAK-140 Basket and pricing",
            openQuestionCount: 1,
            title: "Emit a counter when the checkout total differs from the basket total",
            description: """
                Add a counter that fires when the total the checkout page renders differs from \
                the total the **pricing service** returns for the same basket, so the class of \
                bug behind FAK-231 is visible without a support ticket.
                """
        ),
    ]

    // §12 Rewrite. FAKED IN THE PROTOTYPE LAYER — State has no Rewrite (ticket #26).
    static let rewriteKey = "FAK-231"

    static let rewriteLiveTitle = "Checkout total wrong sometimes"

    static let rewriteLiveBody = """
        Customers say the total is wrong at checkout.

        Sarah reported this again. It seems to be mobile only. Might be caching?

        Needs looking at before the Northbeam renewal.
        """

    static let rewriteComments = [
        "dev · Can't reproduce on desktop. Which browser was she on?",
        "support · Mobile Safari, iOS 18. Happens after editing quantity in the basket.",
        "dev · If it's the pricing call this is the same shape as FAK-198. Needs a repro path "
            + "and an expected/actual before I can pick it up.",
    ]

    static let rewriteProposedBody = """
        **Northbeam** shoppers on mobile web see a checkout total carried over from before \
        their last basket change. The figure corrects itself on a manual refresh, so the \
        **basket** holds the right contents and the **checkout summary** is reading a total \
        it was handed rather than one it asked for.

        Reproduction path: edit the quantity of a basket line on mobile Safari, iOS 18, then \
        continue to checkout. Expected is the recalculated total; actual is the total from \
        before the edit. Desktop is unaffected.

        The checkout summary should recalculate from the shared **pricing service** on load, \
        the same call the basket page has made since FAK-198.
        """
}

struct ChatTurn: Identifiable, Hashable {
    enum Role { case pm, agent }
    let id = UUID()
    var role: Role
    var text: String
}

struct MaterialRow: Identifiable, Hashable {
    enum Kind { case text, screenshot, video }
    let id = UUID()
    var name: String
    var kind: Kind
    var note: String

    var glyph: String {
        switch kind {
        case .text: "doc.text"
        case .screenshot: "photo"
        case .video: "film"
        }
    }
}

struct BatchDraft: Identifiable, Hashable {
    let id = UUID()
    var shortLabel: String
    var ticketType: TicketType
    var epic: String
    var openQuestionCount: Int
    var title: String
    var description: String

    var isComplete: Bool { openQuestionCount == 0 }
}

extension TicketType {
    var label: String {
        switch self {
        case .story: "Story"
        case .bug: "Bug"
        case .chore: "Chore"
        }
    }
}
