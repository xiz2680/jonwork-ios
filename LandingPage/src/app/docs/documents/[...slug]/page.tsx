import { Metadata } from "next";
import { notFound } from "next/navigation";
import { getDocBySlug, getAllDocPaths, fixImagePaths } from "@/lib/docs";
import { MDXRemote } from "next-mdx-remote/rsc";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";
import rehypeAutolinkHeadings from "rehype-autolink-headings";
import { useMDXComponents } from "../../../../../mdx-components";

interface PageProps {
  params: Promise<{
    slug: string[];
  }>;
}

export async function generateStaticParams() {
  return getAllDocPaths();
}

export async function generateMetadata({
  params,
}: PageProps): Promise<Metadata> {
  const { slug } = await params;
  const doc = getDocBySlug(slug);

  if (!doc) {
    return {
      title: "Not Found",
    };
  }

  const fullPath = `/docs/documents/${slug.join("/")}`;

  return {
    title: doc.title,
    description: doc.description,
    alternates: {
      canonical: fullPath,
    },
    openGraph: {
      title: `${doc.title} | FlowDown Docs`,
      description: doc.description,
      type: "article",
      locale: "en_US",
    },
  };
}

export default async function DocPage({ params }: PageProps) {
  const { slug } = await params;
  const doc = getDocBySlug(slug);

  if (!doc) {
    notFound();
  }

  const processedContent = fixImagePaths(doc.content);
  const components = useMDXComponents({});

  return (
    <div>
      <MDXRemote
        source={processedContent}
        options={{
          mdxOptions: {
            remarkPlugins: [remarkGfm],
            rehypePlugins: [
              rehypeSlug,
              [rehypeAutolinkHeadings, { behavior: "wrap" }],
            ],
          },
        }}
        components={components}
      />
    </div>
  );
}
