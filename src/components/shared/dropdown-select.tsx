"use client";

import { Children, Fragment, isValidElement, type ReactElement, type ReactNode } from "react";
import { SelectField, type SelectOption } from "@/components/shared/select-field";

/** The text of an <option>'s children — strings and numbers, joined (a label like `{name} · {n}` is an array). */
function textOf(node: ReactNode): string {
  if (node == null || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement(node)) return textOf((node.props as { children?: ReactNode }).children);
  return "";
}

/** Every <option> under the children, however they are nested (arrays from .map(), fragments). */
function collectOptions(children: ReactNode, out: SelectOption[] = []): SelectOption[] {
  Children.forEach(children, (child) => {
    if (!isValidElement(child)) return;
    if (child.type === Fragment) {
      collectOptions((child.props as { children?: ReactNode }).children, out);
      return;
    }
    if (child.type === "option") {
      const p = (child as ReactElement<{ value?: string | number; disabled?: boolean; children?: ReactNode }>).props;
      const label = textOf(p.children);
      out.push({ value: p.value != null ? String(p.value) : label, label, disabled: p.disabled });
    }
  });
  return out;
}

/** The slice of a change event callers actually read. */
export interface DropdownChangeEvent {
  target: { value: string };
  currentTarget: { value: string };
}

export interface DropdownSelectProps {
  /** Omitted, it shows the first option — like a native select with nothing chosen. */
  value?: string | number;
  onChange?: (e: DropdownChangeEvent) => void;
  disabled?: boolean;
  "aria-label"?: string;
  className?: string;
  /** <option> elements, exactly as for a native <select>. */
  children?: ReactNode;
}

/** Width-type classes belong on the wrapper (a native select sizes itself; our button sits inside a block). */
const WRAPPER_CLASS = /^(w-|min-w-|max-w-|flex-|shrink|grow|basis-|col-span-|self-)/;
const isWrapperToken = (t: string) => WRAPPER_CLASS.test(t.split(":").pop() ?? t);

/**
 * A drop-in for the native <select> that draws its own rounded, themed list instead of the browser's square
 * blue one: same props (`value`, `onChange(e)` reading `e.target.value`, `disabled`, `aria-label`,
 * `className`) and the same <option> children, so switching a screen over is a rename.
 */
export function DropdownSelect({ value, onChange, disabled, className, children, ...rest }: DropdownSelectProps) {
  const options = collectOptions(children);
  const tokens = (className ?? "").split(/\s+/).filter(Boolean);
  const wrapperClassName = tokens.filter(isWrapperToken).join(" ");
  const fieldClassName = tokens.filter((t) => !isWrapperToken(t) && t !== "appearance-none").join(" ");
  return (
    <SelectField
      value={value == null ? (options[0]?.value ?? "") : String(value)}
      onValueChange={(v) => onChange?.({ target: { value: v }, currentTarget: { value: v } })}
      options={options}
      ariaLabel={rest["aria-label"]}
      className={fieldClassName}
      wrapperClassName={wrapperClassName}
      disabled={disabled}
    />
  );
}
