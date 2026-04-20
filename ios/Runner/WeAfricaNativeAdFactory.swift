import Foundation
import GoogleMobileAds
import google_mobile_ads
import UIKit

final class WeAfricaNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(_ nativeAd: GADNativeAd, customOptions: [AnyHashable: Any]? = nil) -> GADNativeAdView {
    let adView = GADNativeAdView(frame: .zero)
    adView.translatesAutoresizingMaskIntoConstraints = false

    let iconView = UIImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentMode = .scaleAspectFill
    iconView.clipsToBounds = true

    let headlineLabel = UILabel()
    headlineLabel.translatesAutoresizingMaskIntoConstraints = false
    headlineLabel.font = UIFont.boldSystemFont(ofSize: 15)
    headlineLabel.numberOfLines = 1

    let bodyLabel = UILabel()
    bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    bodyLabel.font = UIFont.systemFont(ofSize: 13)
    bodyLabel.numberOfLines = 2

    let ctaButton = UIButton(type: .system)
    ctaButton.translatesAutoresizingMaskIntoConstraints = false
    ctaButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
    ctaButton.isUserInteractionEnabled = false

    let textStack = UIStackView(arrangedSubviews: [headlineLabel, bodyLabel])
    textStack.translatesAutoresizingMaskIntoConstraints = false
    textStack.axis = .vertical
    textStack.spacing = 2

    let topRow = UIStackView(arrangedSubviews: [iconView, textStack])
    topRow.translatesAutoresizingMaskIntoConstraints = false
    topRow.axis = .horizontal
    topRow.alignment = .center
    topRow.spacing = 10

    let mainStack = UIStackView(arrangedSubviews: [topRow, ctaButton])
    mainStack.translatesAutoresizingMaskIntoConstraints = false
    mainStack.axis = .vertical
    mainStack.spacing = 10

    adView.addSubview(mainStack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 40),
      iconView.heightAnchor.constraint(equalToConstant: 40),

      mainStack.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
      mainStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
      mainStack.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
      mainStack.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12)
    ])

    // Bind native ad assets.
    headlineLabel.text = nativeAd.headline
    adView.headlineView = headlineLabel

    if let body = nativeAd.body, !body.isEmpty {
      bodyLabel.text = body
      bodyLabel.isHidden = false
      adView.bodyView = bodyLabel
    } else {
      bodyLabel.isHidden = true
    }

    if let icon = nativeAd.icon?.image {
      iconView.image = icon
      iconView.isHidden = false
      adView.iconView = iconView
    } else {
      iconView.isHidden = true
    }

    if let cta = nativeAd.callToAction, !cta.isEmpty {
      ctaButton.setTitle(cta, for: .normal)
      ctaButton.isHidden = false
      adView.callToActionView = ctaButton
    } else {
      ctaButton.isHidden = true
    }

    adView.nativeAd = nativeAd
    return adView
  }
}
