import { buildServer } from '../src/server.ts';
import type { PeopleStore, CommunityStore, ModerationStore } from '../src/contracts.ts';
import type { SharingStore } from '../src/sharing.ts';
import type { ShareDeviceStore } from '../src/share_devices.ts';
import type { SosStore } from '../src/sos.ts';

// Documentation only: denies every token and cannot perform data operations.
// This is also used by the offline OpenAPI exporter, never by src/index.ts.
export async function documentationServer() {
  const denied = async () => {
    throw new Error('Documentation-only instance');
  };
  const people = new Proxy({} as PeopleStore, { get: () => denied });
  const community = new Proxy({} as CommunityStore, { get: () => denied });
  const moderation = new Proxy({} as ModerationStore, { get: () => denied });
  return buildServer({
    people,
    community,
    moderation,
    sharing: new Proxy({} as SharingStore, { get: () => denied }),
    shareDevices: new Proxy({} as ShareDeviceStore, { get: () => denied }),
    sos: new Proxy({} as SosStore, { get: () => denied }),
    reports: { create: denied },
    verifyToken: async () => null,
    inviteToken: () => {
      throw new Error('Documentation-only instance');
    },
  });
}
