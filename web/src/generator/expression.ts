import { Identifier, RuleDeclaration, Node } from "./node";

export class Expression extends Node {
	walk(f: (expr: Expression) => Expression): Expression {
		return f(this);
	}
	eq(_other: Expression): boolean {
		return false;
	}
	prec!: number;
}

Expression.prototype.prec = 10;

export class NameExpression extends Expression {
	readonly id: Identifier;
	readonly args: readonly Expression[];

	constructor(start: number, id: Identifier, args: readonly Expression[]) {
		super(start);
		this.id = id;
		this.args = args;
	}
	toString(): string {
		return this.id.name + (this.args.length ? `<${this.args.join()}>` : "");
	}
	eq(other: NameExpression): boolean {
		return this.id.name == other.id.name && exprsEq(this.args, other.args);
	}
	walk(f: (expr: Expression) => Expression): Expression {
		let args = walkExprs(this.args, f);
		return f(args == this.args ? this : new NameExpression(this.start, this.id, args));
	}
}

export class SpecializeExpression extends Expression {
	readonly type: string;
	readonly props: readonly Prop[];
	readonly token: Expression;
	readonly content: Expression;

	constructor(
		start: number,
		type: string,
		props: readonly Prop[],
		token: Expression,
		content: Expression,
	) {
		super(start);
		this.type = type;
		this.props = props;
		this.token = token;
		this.content = content;
	}
	toString() {
		return `@${this.type}[${this.props.join(",")}]<${this.token}, ${this.content}>`;
	}
	eq(other: SpecializeExpression): boolean {
		return (
			this.type == other.type &&
			Prop.eqProps(this.props, other.props) &&
			exprEq(this.token, other.token) &&
			exprEq(this.content, other.content)
		);
	}
	walk(f: (expr: Expression) => Expression): Expression {
		let token = this.token.walk(f),
			content = this.content.walk(f);
		return f(
			token == this.token && content == this.content
				? this
				: new SpecializeExpression(this.start, this.type, this.props, token, content),
		);
	}
}

export class InlineRuleExpression extends Expression {
	readonly rule: RuleDeclaration;

	constructor(start: number, rule: RuleDeclaration) {
		super(start);
		this.rule = rule;
	}

	toString() {
		let rule = this.rule;
		return `${rule.id}${rule.props.length ? `[${rule.props.join(",")}]` : ""} { ${rule.expr} }`;
	}
	eq(other: InlineRuleExpression): boolean {
		let rule = this.rule,
			oRule = other.rule;
		return (
			exprEq(rule.expr, oRule.expr) &&
			rule.id.name == oRule.id.name &&
			Prop.eqProps(rule.props, oRule.props)
		);
	}
	walk(f: (expr: Expression) => Expression): Expression {
		let rule = this.rule,
			expr = rule.expr.walk(f);
		return f(
			expr == rule.expr
				? this
				: new InlineRuleExpression(
						this.start,
						new RuleDeclaration(rule.start, rule.id, rule.props, [], expr),
					),
		);
	}
}

export class ChoiceExpression extends Expression {
	readonly exprs: readonly Expression[];

	constructor(start: number, exprs: readonly Expression[]) {
		super(start);
		this.exprs = exprs;
	}
	toString(): string {
		return this.exprs.map((e) => maybeParens(e, this)).join(" | ");
	}
	eq(other: ChoiceExpression): boolean {
		return exprsEq(this.exprs, other.exprs);
	}
	walk(f: (expr: Expression) => Expression): Expression {
		let exprs = walkExprs(this.exprs, f);
		return f(exprs == this.exprs ? this : new ChoiceExpression(this.start, exprs));
	}
}

ChoiceExpression.prototype.prec = 1;

export class SequenceExpression extends Expression {
	readonly exprs: readonly Expression[];
	readonly markers: readonly (readonly ConflictMarker[])[];
	readonly empty: boolean;

	constructor(
		start: number,
		exprs: readonly Expression[],
		markers: readonly (readonly ConflictMarker[])[],
		empty = false,
	) {
		super(start);
		this.exprs = exprs;
		this.markers = markers;
		this.empty = empty;
	}
	toString(): string {
		return this.empty ? "()" : this.exprs.map((e) => maybeParens(e, this)).join(" ");
	}
	eq(other: SequenceExpression): boolean {
		return (
			exprsEq(this.exprs, other.exprs) &&
			this.markers.every((m, i) => {
				let om = other.markers[i];
				return m.length == om.length && m.every((x, i) => x.eq(om[i]));
			})
		);
	}
	walk(f: (expr: Expression) => Expression): Expression {
		let exprs = walkExprs(this.exprs, f);
		return f(
			exprs == this.exprs
				? this
				: new SequenceExpression(this.start, exprs, this.markers, this.empty && !exprs.length),
		);
	}
}

SequenceExpression.prototype.prec = 2;

export class ConflictMarker extends Node {
	readonly id: Identifier;
	readonly type: "ambig" | "prec";

	constructor(start: number, id: Identifier, type: "ambig" | "prec") {
		super(start);
		this.id = id;
		this.type = type;
	}

	toString(): string {
		return (this.type == "ambig" ? "~" : "!") + this.id.name;
	}

	eq(other: ConflictMarker): boolean {
		return this.id.name == other.id.name && this.type == other.type;
	}
}

export class RepeatExpression extends Expression {
	readonly expr: Expression;
	readonly kind: "?" | "*" | "+";

	constructor(start: number, expr: Expression, kind: "?" | "*" | "+") {
		super(start);
		this.expr = expr;
		this.kind = kind;
	}
	toString(): string {
		return maybeParens(this.expr, this) + this.kind;
	}
	eq(other: RepeatExpression): boolean {
		return exprEq(this.expr, other.expr) && this.kind == other.kind;
	}
	walk(f: (expr: Expression) => Expression): Expression {
		let expr: Expression = this.expr.walk(f);
		return f(expr == this.expr ? this : new RepeatExpression(this.start, expr, this.kind));
	}
}

RepeatExpression.prototype.prec = 3;

export class LiteralExpression extends Expression {
	readonly value: string;

	constructor(start: number, value: string) {
		super(start);
		this.value = value;
	}
	toString(): string {
		return JSON.stringify(this.value);
	}
	eq(other: LiteralExpression): boolean {
		return this.value == other.value;
	}
}

export class SetExpression extends Expression {
	readonly ranges: [number, number][];
	readonly inverted: boolean;

	constructor(start: number, ranges: [number, number][], inverted: boolean) {
		super(start);
		this.ranges = ranges;
		this.inverted = inverted;
	}
	toString() {
		return `[${this.inverted ? "^" : ""}${this.ranges.map(([a, b]) => {
			return String.fromCodePoint(a) + (b == a + 1 ? "" : "-" + String.fromCodePoint(b));
		})}]`;
	}
	eq(other: SetExpression): boolean {
		return (
			this.inverted == other.inverted &&
			this.ranges.length == other.ranges.length &&
			this.ranges.every(([a, b], i) => {
				let [x, y] = other.ranges[i];
				return a == x && b == y;
			})
		);
	}
}

export class AnyExpression extends Expression {
	constructor(start: number) {
		super(start);
	}
	toString() {
		return "_";
	}
	eq() {
		return true;
	}
}

function walkExprs(
	exprs: readonly Expression[],
	f: (expr: Expression) => Expression,
): readonly Expression[] {
	let result: Expression[] | null = null;
	for (let i = 0; i < exprs.length; i++) {
		let expr = exprs[i].walk(f);
		if (expr != exprs[i] && !result) result = exprs.slice(0, i);
		if (result) result.push(expr);
	}
	return result || exprs;
}

export const CharClasses: { [name: string]: [number, number][] } = {
	asciiLetter: [
		[65, 91],
		[97, 123],
	],
	asciiLowercase: [[97, 123]],
	asciiUppercase: [[65, 91]],
	digit: [[48, 58]],
	whitespace: [
		[9, 14],
		[32, 33],
		[133, 134],
		[160, 161],
		[5760, 5761],
		[8192, 8203],
		[8232, 8234],
		[8239, 8240],
		[8287, 8288],
		[12288, 12289],
	],
	eof: [[0xffff, 0xffff]],
};

export class CharClass extends Expression {
	readonly type: string;

	constructor(start: number, type: string) {
		super(start);
		this.type = type;
	}
	toString(): string {
		return "@" + this.type;
	}
	eq(expr: CharClass): boolean {
		return this.type == expr.type;
	}
}

export function exprEq(a: Expression, b: Expression): boolean {
	return a.constructor == b.constructor && a.eq(b as any);
}

export function exprsEq(a: readonly Expression[], b: readonly Expression[]): boolean {
	return a.length == b.length && a.every((e, i) => exprEq(e, b[i]));
}

export class Prop extends Node {
	readonly at: boolean;
	readonly name: string;
	readonly value: readonly PropPart[];

	constructor(start: number, at: boolean, name: string, value: readonly PropPart[]) {
		super(start);
		this.at = at;
		this.name = name;
		this.value = value;
	}

	eq(other: Prop): boolean {
		return (
			this.name == other.name &&
			this.value.length == other.value.length &&
			this.value.every((v, i) => v.value == other.value[i].value && v.name == other.value[i].name)
		);
	}

	toString(): string {
		let result = (this.at ? "@" : "") + this.name;
		if (this.value.length) {
			result += "=";
			for (let { name, value } of this.value)
				result += name ? `{${name}}` : /[^\w-]/.test(value!) ? JSON.stringify(value) : value;
		}
		return result;
	}

	static eqProps(a: readonly Prop[], b: readonly Prop[]): boolean {
		return a.length == b.length && a.every((p, i) => p.eq(b[i]));
	}
}

export class PropPart extends Node {
	readonly value: string | null;
	readonly name: string | null;

	constructor(start: number, value: string | null, name: string | null) {
		super(start);
		this.value = value;
		this.name = name;
	}
}

function maybeParens(node: Expression, parent: Expression) {
	return node.prec < parent.prec ? "(" + node.toString() + ")" : node.toString();
}
