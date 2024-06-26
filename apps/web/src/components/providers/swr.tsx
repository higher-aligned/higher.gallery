'use client'

import { PropsWithChildren } from 'react'
import { SWRConfig } from 'swr'

async function fetcher(...args: Parameters<typeof fetch>) {
  const response = await fetch(...args)
  return response.json()
}

export function SWRProvider({ children }: PropsWithChildren) {
  return <SWRConfig value={{ fetcher }}>{children}</SWRConfig>
}
