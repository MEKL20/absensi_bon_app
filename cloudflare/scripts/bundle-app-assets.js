import { build } from 'esbuild';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const assets = join(root, '..', 'assets');
mkdirSync(assets, { recursive: true });

await build({
  entryPoints: [join(root, 'src', 'index.js')],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  outfile: join(assets, 'cloudflare_worker.js'),
});

const migrations = readdirSync(join(root, 'migrations'))
  .filter((file) => file.endsWith('.sql'))
  .sort()
  .map((file) => ({ tag: file.replace('.sql', ''), sql: readFileSync(join(root, 'migrations', file), 'utf8') }));
writeFileSync(join(assets, 'cloudflare_migrations.json'), JSON.stringify(migrations, null, 2));
console.log('bundled worker and', migrations.length, 'migrations into', assets);
