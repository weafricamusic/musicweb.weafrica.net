'use client'

import { useEffect } from 'react'

function isMobileViewport() {
	if (typeof window === 'undefined') return false
	return window.matchMedia('(max-width: 767px)').matches
}

export default function AdminDrawerEffects() {
	useEffect(() => {
		const checkbox = document.getElementById('admin-nav') as HTMLInputElement | null
		if (!checkbox) return
		const checkboxEl = checkbox

		const prevOverflow = document.body.style.overflow

		function syncBodyScroll() {
			if (!isMobileViewport()) {
				document.body.style.overflow = prevOverflow
				return
			}
			document.body.style.overflow = checkboxEl.checked ? 'hidden' : prevOverflow
		}

		function onKeyDown(e: KeyboardEvent) {
			if (e.key !== 'Escape') return
			if (!checkboxEl.checked) return
			checkboxEl.checked = false
			syncBodyScroll()
		}

		syncBodyScroll()
		checkboxEl.addEventListener('change', syncBodyScroll)
		window.addEventListener('resize', syncBodyScroll)
		window.addEventListener('keydown', onKeyDown)

		return () => {
			document.body.style.overflow = prevOverflow
			checkboxEl.removeEventListener('change', syncBodyScroll)
			window.removeEventListener('resize', syncBodyScroll)
			window.removeEventListener('keydown', onKeyDown)
		}
	}, [])

	return null
}
