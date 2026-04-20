'use client'

import { type ReactNode, useCallback, useEffect, useMemo, useState } from 'react'
import { usePathname } from 'next/navigation'

const ACCORDION_EVENT = 'weafrica:sidebar-accordion'

function readStoredString(key: string): string | null {
	try {
		return window.localStorage.getItem(key)
	} catch {
		return null
	}
}

function writeStoredString(key: string, value: string) {
	try {
		window.localStorage.setItem(key, value)
	} catch {
		// ignore
	}
}

function accordionOpenKey(accordionKey: string) {
	return `accordion:${accordionKey}:open`
}

export default function CollapsibleGroup(props: {
	label: string
	storageKey: string
	children: ReactNode
	defaultOpen?: boolean
	openOnPrefixes?: string[]
	indent?: boolean
	accordionKey?: string
	icon?: ReactNode
}) {
	const pathname = usePathname()
	const openByPath = useMemo(() => {
		const prefixes = props.openOnPrefixes ?? []
		return prefixes.some((p) => p && pathname.startsWith(p))
	}, [pathname, props.openOnPrefixes])

	const isDashboard = pathname === '/admin/dashboard'
	const accordionKey = props.accordionKey
	const globalKey = accordionKey ? accordionOpenKey(accordionKey) : null

	const [open, setOpen] = useState(() => {
		if (openByPath) return true
		if (props.defaultOpen) return true
		return false
	})

	useEffect(() => {
		function syncOpenFromRouteAndStorage() {
			// Route-based behavior:
			// - Dashboard: everything collapsed by default
			// - Non-dashboard: auto-open the matching group (single-open)
			if (isDashboard) {
				setOpen(false)
				return
			}
			if (!globalKey) {
				if (openByPath) setOpen(true)
				return
			}

			if (openByPath) {
				writeStoredString(globalKey, props.storageKey)
				setOpen(true)
				return
			}

			const stored = typeof window !== 'undefined' ? readStoredString(globalKey) : null
			setOpen(stored === props.storageKey)
		}

		syncOpenFromRouteAndStorage()
	}, [globalKey, isDashboard, openByPath, props.storageKey])

	useEffect(() => {
		if (!globalKey) return

		function onAccordionEvent(e: Event) {
			const detail = (e as CustomEvent).detail as { openKey?: string } | undefined
			const openKey = detail?.openKey
			setOpen(openKey === props.storageKey)
		}

		function onStorage(e: StorageEvent) {
			if (e.key !== globalKey) return
			setOpen(e.newValue === props.storageKey)
		}

		window.addEventListener(ACCORDION_EVENT, onAccordionEvent)
		window.addEventListener('storage', onStorage)
		return () => {
			window.removeEventListener(ACCORDION_EVENT, onAccordionEvent)
			window.removeEventListener('storage', onStorage)
		}
	}, [globalKey, props.storageKey])

	const toggle = useCallback(() => {
		const next = !open
		setOpen(next)

		if (!globalKey || typeof window === 'undefined') return
		const openKey = next ? props.storageKey : ''
		writeStoredString(globalKey, openKey)
		window.dispatchEvent(new CustomEvent(ACCORDION_EVENT, { detail: { openKey } }))
	}, [globalKey, open, props.storageKey])

	return (
		<div className={props.indent === false ? '' : 'mt-1'}>
			<button
				type="button"
				onClick={toggle}
				aria-expanded={open}
				className={
					'group flex w-full items-center justify-between rounded-lg px-4 py-2 text-left text-[12px] font-medium text-zinc-300 hover:bg-white/5'
				}
			>
				<span className="flex items-center gap-2">
					{props.icon ? <span className="text-zinc-400">{props.icon}</span> : null}
					<span>{props.label}</span>
				</span>
				<span className={'text-zinc-500 transition-transform duration-200 ' + (open ? 'rotate-90' : '')}>›</span>
			</button>

			<div className={
				'ml-3 grid overflow-hidden border-l border-white/10 pl-3 transition-[grid-template-rows,opacity] duration-200 ' +
				(open ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0')
			}>
				<div className="min-h-0">
					<div className="space-y-1 py-1">{props.children}</div>
				</div>
			</div>
		</div>
	)
}
