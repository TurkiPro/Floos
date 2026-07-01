/// Whether money flows out (expense) or in (income).
enum TxnType { expense, income }

/// How often a recurring rule fires.
enum Frequency { daily, weekly, monthly, yearly }

/// Whether a category is a necessity (اساسيات) or discretionary (كماليات).
/// Drives the essentials-vs-luxuries breakdown on the statistics screen.
enum CategoryKind { essential, luxury }
