export type StoreCapability =
  | "clipboardRead"
  | "clipboardWrite"
  | "openURL"
  | "notifications"
  | "selectedText"
  | "userSelectedFiles"
  | "networkAccess"
  | "persistentStorage";

export interface StoreFormOption {
  id: string;
  label: string;
}

export interface StoreFormField {
  id: string;
  type:
    | "text"
    | "secureText"
    | "multilineText"
    | "toggle"
    | "select"
    | "file"
    | "files";
  label: string;
  description?: string;
  placeholder?: string;
  required?: boolean;
  defaultValue?: string | boolean;
  options?: StoreFormOption[];
  allowedFileTypes?: string[];
  allowsDirectories?: boolean;
  maximumSelection?: number;
}

export interface StoreCommandForm {
  title?: string;
  description?: string;
  submitLabel?: string;
  fields: StoreFormField[];
}

export interface StoreSelectedFile {
  path: string;
  name: string;
  isDirectory: boolean;
  size?: number;
  contentType?: string;
}

export interface StoreInvocationContext {
  selectedText?: string;
  clipboardText?: string;
  frontmostApplication?: string;
  dataDirectory?: string;
  secrets: Readonly<Record<string, string>>;
  formValues: Readonly<
    Record<string, string | boolean | StoreSelectedFile | StoreSelectedFile[]>
  >;
}

export interface StoreInvocation {
  packageID: string;
  commandID: string;
  query: string;
  context: StoreInvocationContext;
}

export type StoreAction =
  | { type: "copyText"; value: string; label?: string; systemImage?: string }
  | { type: "openURL"; value: string; label?: string; systemImage?: string }
  | { type: "showMessage"; value: string; label?: string; systemImage?: string }
  | {
      type: "notify";
      value: string;
      title?: string;
      label?: string;
      systemImage?: string;
    }
  | {
      /** Store API 4. `value` is an activity id declared under `notch.activities`. */
      type: "notchActivity";
      value: string;
      activity: StoreNotchActivity;
      label?: string;
      systemImage?: string;
    };

/** A live activity in the closed Notch, drawn by Vehla. Nothing of the extension keeps running for it. */
export interface StoreNotchActivity {
  title?: string;
  detail?: string;
  systemImage?: string;
  /** "#RRGGBB" */
  tint?: string;
  /** 0 to 1 */
  progress?: number;
  /** How long it stays: 2 seconds to 8 hours (8 hours when omitted). */
  seconds?: number;
  /** Shows a clock counting down this many seconds in place of `detail`. */
  countdown?: number;
  /** true takes the activity away. */
  end?: boolean;
  /** One of this package's commands, run when the activity is clicked. */
  command?: string;
  query?: string;
  /** At most two. Each runs one of this package's commands. */
  buttons?: { title: string; systemImage?: string; command: string; query?: string }[];
}

export type StoreRichItem =
  | { type: "text" | "markdown" | "code"; text: string; language?: string }
  | { type: "detail"; label: string; value: string };

export interface StoreRichSection {
  title?: string;
  items: StoreRichItem[];
}

export interface StoreRichView {
  title: string;
  subtitle?: string;
  sections?: StoreRichSection[];
  actions?: StoreAction[];
}

export interface StoreResult {
  message?: string;
  action?: StoreAction;
  view?: StoreRichView;
}

export type StoreCommandHandler = (
  invocation: StoreInvocation,
) => StoreResult | void | Promise<StoreResult | void>;

export declare const Store: {
  copyText(value: string): StoreResult;
  openURL(value: string): StoreResult;
  showMessage(value: string): StoreResult;
  notify(title: string, body: string): StoreResult;
  view(value: StoreRichView): StoreResult;
  notchActivity(id: string, activity: StoreNotchActivity): StoreResult;
  endNotchActivity(id: string): StoreResult;
};

export declare function runStoreExtension(handler: StoreCommandHandler): void;
