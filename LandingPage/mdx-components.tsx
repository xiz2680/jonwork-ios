import Link from "next/link";

type MDXComponents = Record<
  string,
  React.ComponentType<React.HTMLAttributes<HTMLElement>>
>;

export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    // Headings with proper styling - matching Landing Page design
    h1: ({ children, ...props }) => (
      <h1
        className="font-['Instrument_Serif'] text-4xl text-[#242424] tracking-[-0.5px] mt-8 mb-4 first:mt-0 [&_a]:no-underline"
        {...props}
      >
        {children}
      </h1>
    ),
    h2: ({ children, ...props }) => (
      <h2
        className="text-2xl font-semibold text-[#242424] mt-10 mb-4 pb-2 border-b border-[#e6e6e6] [&_a]:no-underline"
        {...props}
      >
        {children}
      </h2>
    ),
    h3: ({ children, ...props }) => (
      <h3
        className="text-xl font-semibold text-[#242424] mt-8 mb-3 [&_a]:no-underline"
        {...props}
      >
        {children}
      </h3>
    ),
    h4: ({ children, ...props }) => (
      <h4
        className="text-lg font-medium text-[#242424] mt-6 mb-2 [&_a]:no-underline"
        {...props}
      >
        {children}
      </h4>
    ),

    // Paragraph
    p: ({ children, ...props }) => (
      <p className="text-[#454545] leading-7 mb-4" {...props}>
        {children}
      </p>
    ),

    // Links - using landing page link color, no underline
    a: ({ children, ...props }) => {
      const href = (props as { href?: string }).href;
      const isExternal = href?.startsWith("http");
      if (isExternal) {
        return (
          <a
            href={href}
            target="_blank"
            rel="noopener noreferrer"
            className="text-[#242424] font-medium hover:opacity-70 transition-opacity"
            {...props}
          >
            {children}
          </a>
        );
      }
      return (
        <Link
          href={href || "#"}
          className="text-[#242424] font-medium hover:opacity-70 transition-opacity"
          {...props}
        >
          {children}
        </Link>
      );
    },

    // Lists
    ul: ({ children, ...props }) => (
      <ul
        className="list-disc list-outside ml-5 mb-4 space-y-2 text-[#454545]"
        {...props}
      >
        {children}
      </ul>
    ),
    ol: ({ children, ...props }) => (
      <ol
        className="list-decimal list-outside ml-5 mb-4 space-y-2 text-[#454545]"
        {...props}
      >
        {children}
      </ol>
    ),
    li: ({ children, ...props }) => (
      <li className="leading-7 pl-1" {...props}>
        {children}
      </li>
    ),

    // Code blocks - dark theme matching landing page style
    pre: ({ children, ...props }) => (
      <pre
        className="bg-[#242424] text-[#f6f6f6] rounded-xl p-5 overflow-x-auto mb-6 text-sm font-mono"
        {...props}
      >
        {children}
      </pre>
    ),
    code: ({ children, ...props }) => {
      const isInline = typeof children === "string" && !children.includes("\n");
      if (isInline) {
        return (
          <code
            className="bg-[#ebebeb] text-[#242424] px-1.5 py-0.5 rounded text-sm font-mono"
            {...props}
          >
            {children}
          </code>
        );
      }
      return <code {...props}>{children}</code>;
    },

    // Blockquote - styled with left border
    blockquote: ({ children, ...props }) => (
      <blockquote
        className="border-l-4 border-[#242424] bg-[#ebebeb] pl-4 pr-4 py-3 my-6 text-[#454545] rounded-r-lg"
        {...props}
      >
        {children}
      </blockquote>
    ),

    // Table - clean design
    table: ({ children, ...props }) => (
      <div className="overflow-x-auto mb-6 rounded-xl border border-[#e6e6e6]">
        <table className="min-w-full" {...props}>
          {children}
        </table>
      </div>
    ),
    thead: ({ children, ...props }) => (
      <thead className="bg-[#ebebeb]" {...props}>
        {children}
      </thead>
    ),
    th: ({ children, ...props }) => (
      <th
        className="border-b border-[#e6e6e6] px-4 py-3 text-left font-semibold text-[#242424] text-sm"
        {...props}
      >
        {children}
      </th>
    ),
    td: ({ children, ...props }) => (
      <td
        className="border-b border-[#e6e6e6] px-4 py-3 text-[#454545] text-sm"
        {...props}
      >
        {children}
      </td>
    ),
    tr: ({ children, ...props }) => (
      <tr className="hover:bg-[#ebebeb]/30 transition-colors" {...props}>
        {children}
      </tr>
    ),
    tbody: ({ children, ...props }) => (
      <tbody className="bg-white" {...props}>
        {children}
      </tbody>
    ),

    // Horizontal rule
    hr: (props) => <hr className="my-10 border-[#e6e6e6]" {...props} />,

    // Image
    img: (props) => {
      const { src, alt } = props as { src?: string; alt?: string };
      if (!src) return null;
      return (
        <span className="block my-6">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={src}
            alt={alt || ""}
            className="rounded-xl max-w-full h-auto shadow-sm border border-[#e6e6e6]"
          />
        </span>
      );
    },

    // Strong/bold
    strong: ({ children, ...props }) => (
      <strong className="font-semibold text-[#242424]" {...props}>
        {children}
      </strong>
    ),

    // Emphasis/italic
    em: ({ children, ...props }) => (
      <em className="italic" {...props}>
        {children}
      </em>
    ),

    ...components,
  };
}
