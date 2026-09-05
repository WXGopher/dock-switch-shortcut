import { sendRequest } from "./send-request";

export default async function Command() {
  await sendRequest("mapping");
}
