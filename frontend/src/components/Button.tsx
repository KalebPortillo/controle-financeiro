import { forwardRef, type ButtonHTMLAttributes } from 'react'
import { buttonClass, type ButtonVariant, type ButtonSize } from './buttonClass'

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant
  size?:    ButtonSize
}

export const Button = forwardRef<HTMLButtonElement, Props>(function Button(
  { variant = 'primary', size = 'md', className = '', type = 'button', ...rest },
  ref
) {
  return (
    <button
      ref={ref}
      type={type}
      className={buttonClass({ variant, size, className })}
      {...rest}
    />
  )
})
