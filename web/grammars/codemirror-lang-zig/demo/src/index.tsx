import React, { useCallback, useState } from "react"
import { createRoot } from "react-dom/client"

import type { EditorState } from "@codemirror/state"
import type { TreeCursor } from "@lezer/common"
import { syntaxTree } from "@codemirror/language"

import { Editor } from "./editor.js"
import { initialValue } from "./initialValue.js"

function scan(cursor: TreeCursor, lines: string[], depth = 0) {
	lines.push(`${"  ".repeat(depth)}- ${cursor.name}`)
	if (cursor.firstChild()) {
		do {
			scan(cursor, lines, depth + 1)
		} while (cursor.nextSibling())
		cursor.parent()
	}
}

function Index({}) {
	const [ast, setAST] = useState("")
	const handleChange = useCallback((state: EditorState) => {
		const tree = syntaxTree(state)
		const cursor = tree.cursor()
		const lines: string[] = []
		scan(cursor, lines)
		setAST(lines.join("\n"))
	}, [])

	return (
		<>
			<Editor initialValue={initialValue} onChange={handleChange} />
			<pre className="ast">{ast}</pre>
		</>
	)
}

const main = document.querySelector("main")
if (main === null) {
	throw new Error("failed to select main element")
}

createRoot(main).render(<Index />)
