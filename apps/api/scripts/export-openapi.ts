import { writeFile } from 'node:fs/promises';
import { documentationServer } from './documentation-server.ts';

const app = await documentationServer();
await app.ready();
await writeFile(
  new URL('../../../backend/openapi.json', import.meta.url),
  JSON.stringify(app.swagger(), null, 2) + '\n',
);
await app.close();
console.log('Wrote backend/openapi.json without connecting to Auth or a database.');
