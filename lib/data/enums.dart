/// Whether money flows out (expense) or in (income).
enum TxnType { expense, income }

/// How often a recurring rule fires.
enum Frequency { daily, weekly, monthly, yearly }

/// Whether a category is a necessity (اساسيات) or discretionary (كماليات).
/// Drives the essentials-vs-luxuries breakdown on the statistics screen.
enum CategoryKind { essential, luxury }

/// What an imported bank message involving a given party means.
///
/// The importer stores a disposition rather than just a category because a
/// bank message can mean four different things, and only the user knows which.
/// Stored by index — append new values at the end only.
enum PartyDisposition {
  /// A purchase. The rule's `categoryId` says which category.
  expense,

  /// Money in. The rule's `categoryId` says which income category.
  income,

  /// A deposit toward a goal. The rule's `goalId` says which.
  savings,

  /// The user's own money moving — a card top-up, or a transfer between their
  /// own accounts. Never written to the ledger: the spending it funds is
  /// reported separately by its own messages, so booking this too would count
  /// the same riyals twice.
  ignore,
}
