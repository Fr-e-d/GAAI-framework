// Virtual module type stubs — actual modules are generated at build time by @react-router/dev
import type { ServerBuild } from "react-router";

declare module "virtual:react-router/server-build" {
  export const entry: ServerBuild["entry"];
  export const routes: ServerBuild["routes"];
  export const assets: ServerBuild["assets"];
  export const publicPath: ServerBuild["publicPath"];
  export const assetsBuildDirectory: ServerBuild["assetsBuildDirectory"];
  export const future: ServerBuild["future"];
  export const ssr: ServerBuild["ssr"];
  export const basename: ServerBuild["basename"];
  export const isSpaMode: ServerBuild["isSpaMode"];
  export const routeDiscovery: ServerBuild["routeDiscovery"];
}
