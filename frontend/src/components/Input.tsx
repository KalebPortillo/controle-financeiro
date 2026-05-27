import { forwardRef, type InputHTMLAttributes } from 'react'

type Props = InputHTMLAttributes<HTMLInputElement>

export const Input = forwardRef<HTMLInputElement, Props>(function Input(
  { className = '', ...rest },
  ref
) {
  return (
    <input
      ref={ref}
      className={
        'h-9 w-full rounded-md border border-input bg-background px-3 ' +
        'text-sm text-foreground placeholder:text-muted-foreground ' +
        'focus:border-ring focus:outline-2 focus:outline-ring/30 ' +
        'disabled:opacity-50 disabled:cursor-not-allowed ' +
        className
      }
      {...rest}
    />
  )
})
