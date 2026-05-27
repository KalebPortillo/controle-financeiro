import type { HTMLAttributes } from 'react'

type Props = HTMLAttributes<HTMLDivElement>

export function Card({ className = '', ...rest }: Props) {
  return (
    <div
      className={`rounded-lg border border-border bg-card text-card-foreground ${className}`}
      {...rest}
    />
  )
}

export function CardHeader({ className = '', ...rest }: Props) {
  return <div className={`px-6 pt-6 pb-4 ${className}`} {...rest} />
}

export function CardBody({ className = '', ...rest }: Props) {
  return <div className={`px-6 py-4 ${className}`} {...rest} />
}

export function CardFooter({ className = '', ...rest }: Props) {
  return <div className={`px-6 pt-4 pb-6 ${className}`} {...rest} />
}
