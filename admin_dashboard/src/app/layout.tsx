import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "WeAfrica Music Admin",
    template: "%s · WeAfrica Music Admin",
  },
  description: "WeAfrica Music admin dashboard",
  applicationName: "WeAfrica Music Admin",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    title: "WeAfrica Music Admin",
    statusBarStyle: "default",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">
        {children}
      </body>
    </html>
  );
}
