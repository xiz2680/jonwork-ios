# FlowDown Landing Page

The official landing page for FlowDown - a privacy-first AI chat client for iOS and macOS.

## Tech Stack

- **Framework**: [Next.js 16](https://nextjs.org/) with App Router
- **Styling**: [Tailwind CSS v4](https://tailwindcss.com/)
- **Language**: TypeScript
- **Package Manager**: pnpm
- **Deployment**: Vercel

## Getting Started

### Prerequisites

- Node.js 20+
- pnpm 10+

### Installation

```bash
# Install dependencies
pnpm install

# Start development server
pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) to view the site.

### Commands

| Command      | Description                             |
| ------------ | --------------------------------------- |
| `pnpm dev`   | Start development server with Turbopack |
| `pnpm build` | Build for production                    |
| `pnpm start` | Start production server                 |
| `pnpm lint`  | Run ESLint                              |

## Project Structure

```
LandingPage/
├── src/
│   └── app/
│       ├── layout.tsx    # Root layout
│       ├── page.tsx      # Home page
│       └── globals.css   # Global styles
├── public/               # Static assets
├── next.config.ts        # Next.js configuration
├── tailwind.config.ts    # Tailwind configuration
├── tsconfig.json         # TypeScript configuration
└── package.json          # Dependencies
```

## Deployment

This project is configured for deployment on [Vercel](https://vercel.com/):

1. Connect your GitHub repository to Vercel
2. Set the root directory to `LandingPage`
3. Deploy

## Development Notes

- Uses Tailwind CSS v4 with the new `@theme` directive for custom design tokens
- Supports both light and dark mode via `prefers-color-scheme`
- Fully responsive design
- Optimized for Core Web Vitals

## License

Part of the FlowDown project. See the root LICENSE file for details.
