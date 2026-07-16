export type StoreCapability =
  | "clipboardRead"
  | "clipboardWrite"
  | "openURL"
  | "notifications"
  | "selectedText"
  | "userSelectedFiles"
  | "networkAccess"
  | "persistentStorage";

export interface StoreInvocationContext {
  selectedText?: string;
  clipboardText?: string;
  frontmostApplication?: string;
  dataDirectory?: string;
  secrets: Readonly<Record<string, string>>;
}

export interface StoreInvocation {
  packageID: string;
  commandID: string;
  query: string;
  context: StoreInvocationContext;
}

export type StoreAction =
  | { type: "copyText"; value: string }
  | { type: "openURL"; value: string }
  | { type: "showMessage"; value: string };

export interface StoreResult {
  message?: string;
  action?: StoreAction;
}

export type StoreCommandHandler = (
  invocation: StoreInvocation,
) => StoreResult | void | Promise<StoreResult | void>;

export declare const Store: {
  copyText(value: string): StoreResult;
  openURL(value: string): StoreResult;
  showMessage(value: string): StoreResult;
};

export declare function runStoreExtension(handler: StoreCommandHandler): void;
