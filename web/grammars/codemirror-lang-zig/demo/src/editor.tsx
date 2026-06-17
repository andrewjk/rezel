import React, { useEffect } from "react";

import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { defaultKeymap } from "@codemirror/commands";
import { indentUnit } from "@codemirror/language";
import { basicSetup } from "codemirror";

import { zigLanguage } from "@ndim/codemirror-lang-zig";

import { useCodeMirror } from "./codemirror.js";

const getExtensions = (readOnly: boolean) => [
  indentUnit.of("\t"),
  basicSetup,
  zigLanguage,
  keymap.of(defaultKeymap),
  EditorView.editable.of(!readOnly),
];

interface EditorProps {
  initialValue: string;
  readOnly?: boolean;
  onChange?: (state: EditorState) => void;
}

export function Editor({ initialValue, readOnly, onChange }: EditorProps) {
  const [state, transaction, _, element] = useCodeMirror<HTMLDivElement>({
    doc: initialValue,
    extensions: getExtensions(readOnly ?? false),
  });

  useEffect(() => {
    if (onChange !== undefined && state !== null) {
      if (transaction === null || transaction.docChanged) {
        onChange(state);
      }
    }
  }, [state, transaction]);

  return <div className="editor" ref={element}></div>;
}
