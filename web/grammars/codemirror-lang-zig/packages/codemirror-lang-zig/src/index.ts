import {
	LRLanguage,
	indentNodeProp,
	continuedIndent,
	delimitedIndent,
	foldNodeProp,
	foldInside,
} from "@codemirror/language"

import { parser } from "@ndim/lezer-zig"

export const zigLanguage = LRLanguage.define({
	parser: parser.configure({
		props: [
			indentNodeProp.add({
				"InitList Block ErrBlock SwitchBlock ContainerBlock": delimitedIndent({ closing: "}" }),
				"ParamDeclList FnCallArgs": delimitedIndent({ closing: ")", align: true }),
				AsmParams: delimitedIndent({ closing: ")", align: false }),
				"AsmOutList AsmInList AsmClobList": (context) => context.baseIndent + 2, // ': '
				SwitchProng: (context) => context.baseIndent + context.unit,
				IfStatement: continuedIndent({ except: /^\s*({|else\b)/ }),
				MultiStringLiteral: continuedIndent(),
				WhileStatement: continuedIndent(),
			}),
			foldNodeProp.add({
				"InitList Block ErrBlock SwitchBlock ContainerBlock ParamDeclList FnCallArgs AsmParams": foldInside,
			}),
		],
	}),
	languageData: {
		commentTokens: { line: "//" },
		closeBrackets: { brackets: ["(", "[", "{", "'", '"'] },
		indentOnInput: /^\s*(?:\{|\})$/,
	},
})
