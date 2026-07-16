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
    };

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
};

export declare function runStoreExtension(handler: StoreCommandHandler): void;
