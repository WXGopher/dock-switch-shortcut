import { open, showToast, Toast } from "@raycast/api";
import { RELEASES_URL } from "./constants";
import { DockSwitcherAction, requestDockSwitcher } from "./utils";

export async function sendRequest(action: DockSwitcherAction) {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Opening Dock Switcher...",
  });

  try {
    await requestDockSwitcher(action, open);
    toast.style = Toast.Style.Success;
    toast.title = "Request Sent to Dock Switcher";
    toast.message =
      action === "enable" || action === "disable"
        ? "Confirm status in the app; Allow Raycast Control must be enabled."
        : "View the requested information in the menu bar app.";
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could Not Open Dock Switcher";
    toast.message = error instanceof Error ? error.message : String(error);
    toast.primaryAction = {
      title: "Download Dock Switcher",
      onAction: () => open(RELEASES_URL),
    };
  }
}
