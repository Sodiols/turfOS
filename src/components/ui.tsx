import Link from "next/link";
import { CalendarDays, ArrowUpRight, Goal } from "lucide-react";
export function Brand(){return <Link href="/" className="brand"><Goal aria-hidden="true"/><span>Turf<span className="teal">OS</span></span></Link>}
export function PageTitle({title,description,action}:{title:string;description?:string;action?:React.ReactNode}){return <div className="page-title"><div><h1>{title}</h1>{description&&<p>{description}</p>}</div>{action}</div>}
export function Empty({title="Nothing here yet",description,href,label}:{title?:string;description:string;href?:string;label?:string}){return <div className="empty"><CalendarDays aria-hidden="true" size={32}/><h2>{title}</h2><p>{description}</p>{href&&<Link className="button primary" href={href}>{label}<ArrowUpRight aria-hidden="true" size={16}/></Link>}</div>}
export function Badge({state}:{state:string}){return <span className={`badge ${state}`}>{state.replaceAll("_"," ")}</span>}
export function Panel({title,children,action}:{title?:string;children:React.ReactNode;action?:React.ReactNode}){return <section className="panel">{title&&<div className="panel-head"><h2>{title}</h2>{action}</div>}{children}</section>}
