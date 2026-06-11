import { Expression, LiteralExpression, NameExpression, Prop } from "./expression";

export class Node {
	readonly start: number;
	constructor(start: number) {
		this.start = start;
	}
}

export class GrammarDeclaration extends Node {
	readonly rules: readonly RuleDeclaration[];
	readonly topRules: readonly RuleDeclaration[];
	readonly tokens: TokenDeclaration | null;
	readonly localTokens: readonly LocalTokenDeclaration[];
	readonly context: ContextDeclaration | null;
	readonly externalTokens: readonly ExternalTokenDeclaration[];
	readonly externalSpecializers: readonly ExternalSpecializeDeclaration[];
	readonly externalPropSources: readonly ExternalPropSourceDeclaration[];
	readonly precedences: PrecDeclaration | null;
	readonly mainSkip: Expression | null;
	readonly scopedSkip: readonly {
		expr: Expression;
		topRules: readonly RuleDeclaration[];
		rules: readonly RuleDeclaration[];
	}[];
	readonly dialects: readonly Identifier[];
	readonly externalProps: readonly ExternalPropDeclaration[];
	readonly autoDelim: boolean;

	constructor(
		start: number,
		rules: readonly RuleDeclaration[],
		topRules: readonly RuleDeclaration[],
		tokens: TokenDeclaration | null,
		localTokens: readonly LocalTokenDeclaration[],
		context: ContextDeclaration | null,
		externalTokens: readonly ExternalTokenDeclaration[],
		externalSpecializers: readonly ExternalSpecializeDeclaration[],
		externalPropSources: readonly ExternalPropSourceDeclaration[],
		precedences: PrecDeclaration | null,
		mainSkip: Expression | null,
		scopedSkip: readonly {
			expr: Expression;
			topRules: readonly RuleDeclaration[];
			rules: readonly RuleDeclaration[];
		}[],
		dialects: readonly Identifier[],
		externalProps: readonly ExternalPropDeclaration[],
		autoDelim: boolean,
	) {
		super(start);
		this.rules = rules;
		this.topRules = topRules;
		this.tokens = tokens;
		this.localTokens = localTokens;
		this.context = context;
		this.externalTokens = externalTokens;
		this.externalSpecializers = externalSpecializers;
		this.externalPropSources = externalPropSources;
		this.precedences = precedences;
		this.mainSkip = mainSkip;
		this.scopedSkip = scopedSkip;
		this.dialects = dialects;
		this.externalProps = externalProps;
		this.autoDelim = autoDelim;
	}
	toString(): string {
		return Object.values(this.rules).join("\n");
	}
}

export class RuleDeclaration extends Node {
	readonly id: Identifier;
	readonly props: readonly Prop[];
	readonly params: readonly Identifier[];
	readonly expr: Expression;

	constructor(
		start: number,
		id: Identifier,
		props: readonly Prop[],
		params: readonly Identifier[],
		expr: Expression,
	) {
		super(start);
		this.id = id;
		this.props = props;
		this.params = params;
		this.expr = expr;
	}
	toString(): string {
		return (
			this.id.name + (this.params.length ? `<${this.params.join()}>` : "") + " -> " + this.expr
		);
	}
}

export class PrecDeclaration extends Node {
	readonly items: readonly { id: Identifier; type: "left" | "right" | "cut" | null }[];

	constructor(
		start: number,
		items: readonly { id: Identifier; type: "left" | "right" | "cut" | null }[],
	) {
		super(start);
		this.items = items;
	}
}

export class TokenPrecDeclaration extends Node {
	readonly items: readonly (NameExpression | LiteralExpression)[];

	constructor(start: number, items: readonly (NameExpression | LiteralExpression)[]) {
		super(start);
		this.items = items;
	}
}

export class TokenConflictDeclaration extends Node {
	readonly a: NameExpression | LiteralExpression;
	readonly b: NameExpression | LiteralExpression;

	constructor(
		start: number,
		a: NameExpression | LiteralExpression,
		b: NameExpression | LiteralExpression,
	) {
		super(start);
		this.a = a;
		this.b = b;
	}
}

export class TokenDeclaration extends Node {
	readonly precedences: readonly TokenPrecDeclaration[];
	readonly conflicts: readonly TokenConflictDeclaration[];
	readonly rules: readonly RuleDeclaration[];
	readonly literals: readonly LiteralDeclaration[];

	constructor(
		start: number,
		precedences: readonly TokenPrecDeclaration[],
		conflicts: readonly TokenConflictDeclaration[],
		rules: readonly RuleDeclaration[],
		literals: readonly LiteralDeclaration[],
	) {
		super(start);
		this.precedences = precedences;
		this.conflicts = conflicts;
		this.rules = rules;
		this.literals = literals;
	}
}

export class LocalTokenDeclaration extends Node {
	readonly precedences: readonly TokenPrecDeclaration[];
	readonly rules: readonly RuleDeclaration[];
	readonly fallback: { readonly id: Identifier; readonly props: readonly Prop[] } | null;

	constructor(
		start: number,
		precedences: readonly TokenPrecDeclaration[],
		rules: readonly RuleDeclaration[],
		fallback: { readonly id: Identifier; readonly props: readonly Prop[] } | null,
	) {
		super(start);
		this.precedences = precedences;
		this.rules = rules;
		this.fallback = fallback;
	}
}

export class LiteralDeclaration extends Node {
	readonly literal: string;
	readonly props: readonly Prop[];

	constructor(start: number, literal: string, props: readonly Prop[]) {
		super(start);
		this.literal = literal;
		this.props = props;
	}
}

export class ContextDeclaration extends Node {
	readonly id: Identifier;
	readonly source: string;

	constructor(start: number, id: Identifier, source: string) {
		super(start);
		this.id = id;
		this.source = source;
	}
}

export class ExternalTokenDeclaration extends Node {
	readonly id: Identifier;
	readonly source: string;
	readonly tokens: readonly { id: Identifier; props: readonly Prop[] }[];
	readonly conflicts: readonly Identifier[];

	constructor(
		start: number,
		id: Identifier,
		source: string,
		tokens: readonly { id: Identifier; props: readonly Prop[] }[],
		conflicts: readonly Identifier[],
	) {
		super(start);
		this.id = id;
		this.source = source;
		this.tokens = tokens;
		this.conflicts = conflicts;
	}
}

export class ExternalSpecializeDeclaration extends Node {
	readonly type: "extend" | "specialize";
	readonly token: Expression;
	readonly id: Identifier;
	readonly source: string;
	readonly tokens: readonly { id: Identifier; props: readonly Prop[] }[];

	constructor(
		start: number,
		type: "extend" | "specialize",
		token: Expression,
		id: Identifier,
		source: string,
		tokens: readonly { id: Identifier; props: readonly Prop[] }[],
	) {
		super(start);
		this.type = type;
		this.token = token;
		this.id = id;
		this.source = source;
		this.tokens = tokens;
	}
}

export class ExternalPropSourceDeclaration extends Node {
	readonly id: Identifier;
	readonly source: string;

	constructor(start: number, id: Identifier, source: string) {
		super(start);
		this.id = id;
		this.source = source;
	}
}

export class ExternalPropDeclaration extends Node {
	readonly id: Identifier;
	readonly externalID: Identifier;
	readonly source: string;

	constructor(start: number, id: Identifier, externalID: Identifier, source: string) {
		super(start);
		this.id = id;
		this.externalID = externalID;
		this.source = source;
	}
}

export class Identifier extends Node {
	readonly name: string;

	constructor(start: number, name: string) {
		super(start);
		this.name = name;
	}
	toString(): string {
		return this.name;
	}
}
