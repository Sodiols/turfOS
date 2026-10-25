import type { Metadata } from "next";
import "./globals.css";
export const metadata:Metadata={title:{default:"TurfOS | Sports facility operations",template:"%s | TurfOS"},description:"One clear schedule. Manage facility bookings, customer records and manual payments in a private business workspace."};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body><a href="#main" className="skip">Skip to content</a>{children}</body></html>}
