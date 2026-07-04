import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://gfriloux.github.io',
  base: '/stc',
  integrations: [
    starlight({
      title: 'STC',
      tagline: 'Standard Template Construct',
      description:
        'The sacred repository of the Adeptus Technicus — a Nix module library for the discerning Techpriest.',
      logo: {
        alt: 'STC · Adeptus Mechanicus Cog',
        src: './src/assets/stc-emblem.svg',
      },
      head: [
        { tag: 'link', attrs: { rel: 'preconnect', href: 'https://fonts.googleapis.com' } },
        { tag: 'link', attrs: { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: true } },
        { tag: 'link', attrs: {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Cinzel:wght@500;600;700;800&family=IBM+Plex+Sans:wght@400;500;600&family=JetBrains+Mono:ital,wght@0,400;0,500;0,700;1,400&display=swap',
        } },
        { tag: 'script', attrs: { src: '/stc/stc-fx.js', defer: true } },
      ],
      components: {
        Hero: './src/components/Hero.astro',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/gfriloux/stc',
        },
      ],
      defaultLocale: 'en',
      locales: {
        en: {
          label: 'English',
          lang: 'en',
        },
        fr: {
          label: 'Français',
          lang: 'fr',
        },
      },
      sidebar: [
        {
          label: 'The Archivum',
          translations: { fr: "L'Archivum" },
          items: [
            { slug: 'index' },
            { slug: 'getting-started' },
            { slug: 'architecture' },
          ],
        },
        {
          label: 'Relics',
          translations: { fr: 'Reliques' },
          collapsed: false,
          autogenerate: { directory: 'relics' },
        },
        {
          label: 'Cogitator',
          collapsed: false,
          autogenerate: { directory: 'cogitator' },
        },
        {
          label: 'Forge',
          translations: { fr: 'La Forge' },
          collapsed: false,
          autogenerate: { directory: 'forge' },
        },
        {
          label: 'Schematics',
          translations: { fr: 'Schémas' },
          collapsed: true,
          autogenerate: { directory: 'schematics' },
        },
        {
          label: 'Provings',
          translations: { fr: 'Épreuves' },
          collapsed: true,
          autogenerate: { directory: 'provings' },
        },
        {
          label: 'Reference',
          translations: { fr: 'Référence' },
          collapsed: true,
          autogenerate: { directory: 'reference' },
        },
      ],
      customCss: ['./src/styles/stc.css'],
    }),
  ],
});
