export type DockSwitcherAction = "enable" | "disable" | "mapping" | "settings";

const ACTION_URLS: Record<DockSwitcherAction, string> = {
  enable: "dockswitcher://enable",
  disable: "dockswitcher://disable",
  mapping: "dockswitcher://mapping",
  settings: "dockswitcher://settings",
};

export const APP_OPEN_ERROR =
  "Install Dock Switcher.app from GitHub Releases, move it to Applications, and open it once. Then retry this command.";

export function getDockSwitcherURL(action: string): string {
  if (!Object.prototype.hasOwnProperty.call(ACTION_URLS, action)) {
    throw new Error("Unsupported Dock Switcher action");
  }
  return ACTION_URLS[action as DockSwitcherAction];
}

export async function requestDockSwitcher(
  action: DockSwitcherAction,
  openURL: (url: string) => Promise<void>,
): Promise<void> {
  const url = getDockSwitcherURL(action);
  try {
    await openURL(url);
  } catch {
    throw new Error(APP_OPEN_ERROR);
  }
}
